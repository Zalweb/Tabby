-- Private payment destinations owned by a Tabby user.
-- QR images are never public; debtors receive only a signed URL after the RPC
-- verifies the requested bilateral tab and current balance.

CREATE TABLE IF NOT EXISTS public.payment_methods (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    provider TEXT NOT NULL CHECK (length(trim(provider)) > 0),
    display_name TEXT NOT NULL CHECK (length(trim(display_name)) > 0),
    account_label TEXT NOT NULL DEFAULT '',
    qr_storage_path TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    is_default BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_payment_methods_owner
    ON public.payment_methods(owner_user_id, is_active, created_at);

CREATE UNIQUE INDEX IF NOT EXISTS idx_payment_methods_one_default
    ON public.payment_methods(owner_user_id)
    WHERE is_active AND is_default;

ALTER TABLE public.payment_methods ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Owners can view their payment methods"
    ON public.payment_methods;
CREATE POLICY "Owners can view their payment methods"
    ON public.payment_methods FOR SELECT TO authenticated
    USING (owner_user_id = auth.uid());

DROP POLICY IF EXISTS "Owners can create payment methods"
    ON public.payment_methods;
CREATE POLICY "Owners can create payment methods"
    ON public.payment_methods FOR INSERT TO authenticated
    WITH CHECK (owner_user_id = auth.uid());

DROP POLICY IF EXISTS "Owners can update payment methods"
    ON public.payment_methods;
CREATE POLICY "Owners can update payment methods"
    ON public.payment_methods FOR UPDATE TO authenticated
    USING (owner_user_id = auth.uid())
    WITH CHECK (owner_user_id = auth.uid());

DROP POLICY IF EXISTS "Owners can delete payment methods"
    ON public.payment_methods;
CREATE POLICY "Owners can delete payment methods"
    ON public.payment_methods FOR DELETE TO authenticated
    USING (owner_user_id = auth.uid());

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'storage' AND table_name = 'buckets'
    ) THEN
        INSERT INTO storage.buckets
            (id, name, public, file_size_limit, allowed_mime_types)
        VALUES (
            'payment-methods',
            'payment-methods',
            FALSE,
            10485760,
            ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/jpg']
        )
        ON CONFLICT (id) DO UPDATE SET
            public = FALSE,
            file_size_limit = 10485760,
            allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/jpg'];

        DROP POLICY IF EXISTS "Owners can upload payment methods" ON storage.objects;
        CREATE POLICY "Owners can upload payment methods"
            ON storage.objects FOR INSERT TO authenticated
            WITH CHECK (
                bucket_id = 'payment-methods'
                AND (storage.foldername(name))[1] = auth.uid()::text
            );

        DROP POLICY IF EXISTS "Owners can update payment methods files" ON storage.objects;
        CREATE POLICY "Owners can update payment methods files"
            ON storage.objects FOR UPDATE TO authenticated
            USING (
                bucket_id = 'payment-methods'
                AND (storage.foldername(name))[1] = auth.uid()::text
            )
            WITH CHECK (
                bucket_id = 'payment-methods'
                AND (storage.foldername(name))[1] = auth.uid()::text
            );

        DROP POLICY IF EXISTS "Owners can delete payment methods files" ON storage.objects;
        CREATE POLICY "Owners can delete payment methods files"
            ON storage.objects FOR DELETE TO authenticated
            USING (
                bucket_id = 'payment-methods'
                AND (storage.foldername(name))[1] = auth.uid()::text
            );

        DROP POLICY IF EXISTS "Authorized debtors can view payment methods files" ON storage.objects;
        CREATE POLICY "Authorized debtors can view payment methods files"
            ON storage.objects FOR SELECT TO authenticated
            USING (
                bucket_id = 'payment-methods'
                AND EXISTS (
                    SELECT 1
                    FROM public.payment_methods pm
                    WHERE pm.qr_storage_path = name
                      AND (
                          pm.owner_user_id = auth.uid()
                          OR EXISTS (
                              SELECT 1
                              FROM public.tabs t
                              WHERE t.tab_type = 'individual'
                                AND t.status = 'active'
                                AND ((t.user_a = auth.uid() AND t.user_b = pm.owner_user_id)
                                  OR (t.user_b = auth.uid() AND t.user_a = pm.owner_user_id))
                                AND public.get_net_balance(t.id, auth.uid()) < 0
                          )
                      )
                )
            );
    END IF;
END $$;

-- Use a narrowly scoped RPC for debtor access. Signed URL creation remains in
-- the client after this function returns authorized method rows.
CREATE OR REPLACE FUNCTION public.list_payment_methods_for_tab(
    p_tab_id UUID,
    p_payee_user_id UUID
)
RETURNS TABLE (
    id UUID,
    owner_user_id UUID,
    provider TEXT,
    display_name TEXT,
    account_label TEXT,
    qr_storage_path TEXT,
    is_active BOOLEAN,
    is_default BOOLEAN,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
) AS $$
DECLARE
    v_balance BIGINT;
BEGIN
    IF auth.uid() IS NULL OR p_tab_id IS NULL OR p_payee_user_id IS NULL
       OR p_payee_user_id = auth.uid() THEN
        RETURN;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.tabs t
        WHERE t.id = p_tab_id
          AND t.tab_type = 'individual'
          AND t.status = 'active'
          AND ((t.user_a = auth.uid() AND t.user_b = p_payee_user_id)
            OR (t.user_b = auth.uid() AND t.user_a = p_payee_user_id))
    ) THEN
        RETURN;
    END IF;

    v_balance := public.get_net_balance(p_tab_id, auth.uid());
    IF v_balance >= 0 THEN
        RETURN;
    END IF;

    RETURN QUERY
    SELECT pm.id, pm.owner_user_id, pm.provider, pm.display_name,
           pm.account_label, pm.qr_storage_path, pm.is_active, pm.is_default,
           pm.created_at, pm.updated_at
    FROM public.payment_methods pm
    WHERE pm.owner_user_id = p_payee_user_id
      AND pm.is_active = TRUE
    ORDER BY pm.is_default DESC, pm.created_at ASC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.list_payment_methods_for_tab(UUID, UUID)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_payment_methods_for_tab(UUID, UUID)
    TO authenticated;

-- Preserve existing payment destinations for users already on the legacy
-- profile columns when those optional columns still exist. The live schema may
-- already have removed them, so keep this compatibility backfill conditional.
DO $backfill$
BEGIN
    IF (
        SELECT count(*)
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'users'
          AND column_name IN ('gcash_number', 'maya_number', 'qr_code_url')
    ) = 3 THEN
        EXECUTE $sql$
        INSERT INTO public.payment_methods (
            owner_user_id, provider, display_name, account_label,
            qr_storage_path, is_default
        )
        SELECT u.id,
               CASE WHEN nullif(trim(u.gcash_number), '') IS NOT NULL THEN 'gcash'
                    WHEN nullif(trim(u.maya_number), '') IS NOT NULL THEN 'maya'
                    ELSE 'other' END,
               CASE WHEN nullif(trim(u.gcash_number), '') IS NOT NULL THEN 'GCash'
                    WHEN nullif(trim(u.maya_number), '') IS NOT NULL THEN 'Maya'
                    ELSE 'Payment QR' END,
               COALESCE(nullif(trim(u.gcash_number), ''), nullif(trim(u.maya_number), ''), ''),
               nullif(trim(u.qr_code_url), ''),
               TRUE
        FROM public.users u
        WHERE (nullif(trim(u.gcash_number), '') IS NOT NULL
            OR nullif(trim(u.maya_number), '') IS NOT NULL
            OR nullif(trim(u.qr_code_url), '') IS NOT NULL)
          AND NOT EXISTS (
              SELECT 1 FROM public.payment_methods pm
              WHERE pm.owner_user_id = u.id
          )
        $sql$;
    END IF;
END
$backfill$;
