CREATE TABLE public.transaction_receipt_revisions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  transaction_id UUID NOT NULL REFERENCES public.transactions(id) ON DELETE RESTRICT,
  uploaded_by UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  operation_id UUID NOT NULL,
  storage_path TEXT NOT NULL,
  uploaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(uploaded_by,operation_id)
);
ALTER TABLE public.transaction_receipt_revisions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.transaction_receipt_revisions FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.transaction_receipt_revisions TO authenticated;
CREATE FUNCTION public.can_view_transaction_receipts(p_transaction_id UUID)
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER STABLE SET search_path=public,pg_temp AS $$
  SELECT auth.uid() IS NOT NULL AND EXISTS(SELECT 1 FROM public.transactions t
    WHERE t.id=p_transaction_id AND public.is_tab_member(t.tab_id,auth.uid()));
$$;
REVOKE ALL ON FUNCTION public.can_view_transaction_receipts(UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_view_transaction_receipts(UUID) TO authenticated;
CREATE POLICY "Tab members read receipt revisions" ON public.transaction_receipt_revisions FOR SELECT TO authenticated
  USING(public.can_view_transaction_receipts(transaction_id));
REVOKE UPDATE,DELETE ON public.transactions FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.append_transaction_receipt_v1(p_operation_id UUID,p_command JSONB)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  v_actor UUID:=auth.uid();
  v_transaction UUID:=(p_command->>'transaction_id')::UUID;
  v_path TEXT:=p_command->>'proof_path';
  v_previous public.transaction_receipt_revisions%ROWTYPE;
  v_result UUID;
BEGIN
  IF v_actor IS NULL OR NOT EXISTS(SELECT 1 FROM public.transactions t WHERE t.id=v_transaction
      AND public.is_tab_member(t.tab_id,v_actor)) THEN
    RAISE EXCEPTION 'Tab membership required' USING ERRCODE='42501';
  END IF;
  IF p_operation_id IS NULL OR nullif(v_path,'') IS NULL THEN
    RAISE EXCEPTION 'Operation and uploaded receipt required' USING ERRCODE='22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('transaction-receipt:'||v_actor::TEXT||':'||p_operation_id::TEXT,0));
  SELECT * INTO v_previous FROM public.transaction_receipt_revisions WHERE uploaded_by=v_actor AND operation_id=p_operation_id;
  IF FOUND THEN
    IF v_previous.transaction_id IS DISTINCT FROM v_transaction OR v_previous.storage_path IS DISTINCT FROM v_path THEN
      RAISE EXCEPTION 'Receipt operation reused with different content' USING ERRCODE='22023';
    END IF;
    RETURN v_previous.id;
  END IF;
  IF v_path NOT LIKE v_actor::TEXT||'/%' OR v_path ~ '(^|/)\.\.(/|$)' OR NOT EXISTS(
    SELECT 1 FROM storage.objects o WHERE o.bucket_id='payment-proofs' AND o.name=v_path) THEN
    RAISE EXCEPTION 'Receipt must reference your uploaded private object' USING ERRCODE='42501';
  END IF;
  INSERT INTO public.transaction_receipt_revisions(transaction_id,uploaded_by,operation_id,storage_path)
    VALUES(v_transaction,v_actor,p_operation_id,v_path) RETURNING id INTO v_result;
  RETURN v_result;
END; $$;
REVOKE ALL ON FUNCTION public.append_transaction_receipt_v1(UUID,JSONB) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.append_transaction_receipt_v1(UUID,JSONB) TO authenticated;

CREATE OR REPLACE FUNCTION public.can_read_payment_proof_object(p_path TEXT)
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER STABLE SET search_path=public,pg_temp AS $$
  SELECT auth.uid() IS NOT NULL AND (
    p_path LIKE auth.uid()::TEXT||'/%' OR EXISTS(
      SELECT 1 FROM public.payment_proofs pp WHERE pp.file_url=p_path AND public.can_view_payment_proofs(pp.payment_id))
    OR EXISTS(SELECT 1 FROM public.transactions t WHERE t.receipt_url=p_path AND public.is_tab_member(t.tab_id,auth.uid()))
    OR EXISTS(SELECT 1 FROM public.transaction_receipt_revisions r JOIN public.transactions t ON t.id=r.transaction_id
      WHERE r.storage_path=p_path AND public.is_tab_member(t.tab_id,auth.uid())));
$$;
CREATE OR REPLACE FUNCTION public.can_mutate_unreferenced_proof(p_path TEXT)
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER STABLE SET search_path=public,pg_temp AS $$
  SELECT auth.uid() IS NOT NULL AND p_path LIKE auth.uid()::TEXT||'/%'
    AND NOT EXISTS(SELECT 1 FROM public.payment_proofs pp WHERE pp.file_url=p_path)
    AND NOT EXISTS(SELECT 1 FROM public.transactions t WHERE t.receipt_url=p_path)
    AND NOT EXISTS(SELECT 1 FROM public.transaction_receipt_revisions r WHERE r.storage_path=p_path);
$$;
