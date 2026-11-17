BEGIN;
ALTER TABLE public.payment_methods ADD COLUMN revision INTEGER NOT NULL DEFAULT 1;
CREATE TABLE public.payment_method_revisions (
    method_id UUID NOT NULL REFERENCES public.payment_methods(id) ON DELETE RESTRICT,
    owner_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    revision INTEGER NOT NULL, snapshot JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (method_id, revision)
);
CREATE TABLE public.payment_method_operations (
    actor_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    operation_id UUID NOT NULL, kind TEXT NOT NULL, command JSONB NOT NULL,
    result JSONB NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (actor_id,operation_id)
);
ALTER TABLE public.payment_method_revisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payment_method_operations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.payment_method_revisions,public.payment_method_operations FROM anon,authenticated;
CREATE POLICY "Owners can read method revisions" ON public.payment_method_revisions
    FOR SELECT TO authenticated USING (owner_user_id=auth.uid());
GRANT SELECT ON public.payment_method_revisions TO authenticated;

-- Repair preference gaps in nonfinancial method metadata, preserving an existing preference.
DO $$
DECLARE v_owner UUID; v_selected UUID;
BEGIN
    FOR v_owner IN SELECT DISTINCT owner_user_id FROM public.payment_methods WHERE is_active LOOP
        SELECT id INTO v_selected FROM public.payment_methods
            WHERE owner_user_id=v_owner AND is_active
            ORDER BY is_default DESC,created_at,id LIMIT 1;
        UPDATE public.payment_methods SET is_default=false WHERE owner_user_id=v_owner AND is_default;
        UPDATE public.payment_methods SET is_default=true WHERE id=v_selected;
    END LOOP;
END $$;
INSERT INTO public.payment_method_revisions(method_id,owner_user_id,revision,snapshot)
    SELECT id,owner_user_id,revision,to_jsonb(pm) FROM public.payment_methods pm;

CREATE OR REPLACE FUNCTION public.change_payment_method_v1(
    p_operation_id UUID, p_kind TEXT, p_command JSONB
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER
SET search_path=public,pg_temp AS $$
DECLARE
    v_actor UUID := auth.uid(); v_id UUID; v_previous public.payment_methods;
    v_current public.payment_methods; v_operation public.payment_method_operations;
    v_path TEXT; v_default BOOLEAN; v_result JSONB; v_successor UUID;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'Sign in required' USING ERRCODE='42501'; END IF;
    IF p_operation_id IS NULL OR p_kind IS NULL OR p_kind NOT IN ('save','prefer','remove')
       OR p_command IS NULL OR jsonb_typeof(p_command)<>'object' THEN
        RAISE EXCEPTION 'Invalid method command' USING ERRCODE='22023';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtextextended('payment-methods:'||v_actor::text,0));
    SELECT * INTO v_operation FROM public.payment_method_operations
        WHERE actor_id=v_actor AND operation_id=p_operation_id;
    IF FOUND THEN
        IF v_operation.kind<>p_kind OR v_operation.command<>p_command THEN
            RAISE EXCEPTION 'Operation payload conflict' USING ERRCODE='22023';
        END IF;
        RETURN v_operation.result;
    END IF;
    v_id := (p_command->>'method_id')::uuid;
    IF v_id IS NULL THEN RAISE EXCEPTION 'Method ID required' USING ERRCODE='22023'; END IF;
    SELECT * INTO v_previous FROM public.payment_methods WHERE id=v_id FOR UPDATE;
    IF FOUND AND v_previous.owner_user_id<>v_actor THEN
        RAISE EXCEPTION 'Method is not owned by caller' USING ERRCODE='42501';
    END IF;
    IF p_kind='save' THEN
        IF nullif(trim(p_command->>'provider'),'') IS NULL
           OR nullif(trim(p_command->>'display_name'),'') IS NULL THEN
            RAISE EXCEPTION 'Method name/provider required' USING ERRCODE='22023';
        END IF;
        IF (v_previous.id IS NULL AND p_command->>'expected_revision' IS NOT NULL)
           OR (v_previous.id IS NOT NULL AND (
             NOT v_previous.is_active OR p_command->>'expected_revision' IS NULL
             OR (p_command->>'expected_revision')::integer<>v_previous.revision)) THEN
            RAISE EXCEPTION 'Method changed; refresh before editing' USING ERRCODE='40001';
        END IF;
        v_path := nullif(p_command->>'qr_storage_path','');
        IF v_path IS NOT NULL AND (v_previous.id IS NULL OR v_path IS DISTINCT FROM v_previous.qr_storage_path) THEN
            IF split_part(v_path,'/',1)<>v_actor::text OR NOT EXISTS (
                SELECT 1 FROM storage.objects WHERE bucket_id='payment-methods' AND name=v_path
            ) THEN RAISE EXCEPTION 'Upload the receiving QR first' USING ERRCODE='42501'; END IF;
        END IF;
        v_default := coalesce((p_command->>'make_default')::boolean,false)
            OR coalesce(v_previous.is_default,false)
            OR NOT EXISTS (SELECT 1 FROM public.payment_methods WHERE owner_user_id=v_actor AND is_active);
        IF v_default THEN
            UPDATE public.payment_methods SET is_default=false,revision=revision+1,updated_at=now()
                WHERE owner_user_id=v_actor AND is_default AND id<>v_id;
        END IF;
        INSERT INTO public.payment_methods(id,owner_user_id,provider,display_name,account_label,
            qr_storage_path,is_default,revision)
        VALUES(v_id,v_actor,trim(p_command->>'provider'),trim(p_command->>'display_name'),
            coalesce(p_command->>'account_label',''),v_path,v_default,1)
        ON CONFLICT(id) DO UPDATE SET provider=EXCLUDED.provider,display_name=EXCLUDED.display_name,
            account_label=EXCLUDED.account_label,qr_storage_path=EXCLUDED.qr_storage_path,
            is_default=v_default,revision=payment_methods.revision+1,updated_at=now();
    ELSE
        IF v_previous.id IS NULL OR NOT v_previous.is_active THEN
            RAISE EXCEPTION 'Active method not found' USING ERRCODE='22023';
        END IF;
        IF p_kind='prefer' THEN
            UPDATE public.payment_methods SET is_default=false,revision=revision+1,updated_at=now()
                WHERE owner_user_id=v_actor AND is_default AND id<>v_id;
            UPDATE public.payment_methods SET is_default=true,revision=revision+1,updated_at=now() WHERE id=v_id;
        ELSE
            UPDATE public.payment_methods SET is_active=false,is_default=false,revision=revision+1,updated_at=now() WHERE id=v_id;
            IF v_previous.is_default THEN
                SELECT id INTO v_successor FROM public.payment_methods WHERE owner_user_id=v_actor AND is_active
                    ORDER BY created_at,id LIMIT 1;
                UPDATE public.payment_methods SET is_default=true,revision=revision+1,updated_at=now() WHERE id=v_successor;
            END IF;
        END IF;
    END IF;
    SELECT * INTO v_current FROM public.payment_methods WHERE id=v_id;
    -- Record every metadata row changed by this command, including promotion/demotion.
    INSERT INTO public.payment_method_revisions(method_id,owner_user_id,revision,snapshot)
        SELECT id,owner_user_id,revision,to_jsonb(pm) FROM public.payment_methods pm
        WHERE owner_user_id=v_actor
        ON CONFLICT(method_id,revision) DO NOTHING;
    v_result := to_jsonb(v_current);
    INSERT INTO public.payment_method_operations(actor_id,operation_id,kind,command,result)
        VALUES(v_actor,p_operation_id,p_kind,p_command,v_result);
    RETURN v_result;
END $$;
REVOKE ALL ON FUNCTION public.change_payment_method_v1(UUID,TEXT,JSONB) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.change_payment_method_v1(UUID,TEXT,JSONB) TO authenticated;
REVOKE INSERT,UPDATE,DELETE ON public.payment_methods FROM anon,authenticated;

-- Replacement always uses a new object path; referenced revisions stay immutable.
CREATE OR REPLACE FUNCTION public.is_payment_method_file_referenced(p_name TEXT)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
    SELECT EXISTS(SELECT 1 FROM public.payment_methods WHERE qr_storage_path=p_name)
       OR EXISTS(SELECT 1 FROM public.payment_method_revisions WHERE snapshot->>'qr_storage_path'=p_name);
$$;
REVOKE ALL ON FUNCTION public.is_payment_method_file_referenced(TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.is_payment_method_file_referenced(TEXT) TO authenticated;
DROP POLICY IF EXISTS "Owners can update payment methods files" ON storage.objects;
DROP POLICY IF EXISTS "Owners can delete payment methods files" ON storage.objects;
CREATE POLICY "Owners can delete unreferenced method files" ON storage.objects
    FOR DELETE TO authenticated USING (bucket_id='payment-methods'
      AND split_part(name,'/',1)=auth.uid()::text AND NOT public.is_payment_method_file_referenced(name));
COMMIT;
