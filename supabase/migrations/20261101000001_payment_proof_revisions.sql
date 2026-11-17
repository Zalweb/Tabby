ALTER TABLE public.payment_proofs ADD COLUMN operation_id UUID;
ALTER TABLE public.payment_proofs ADD COLUMN uploaded_by UUID REFERENCES public.users(id) ON DELETE RESTRICT;
ALTER TABLE public.payment_proofs ADD COLUMN reference TEXT;
CREATE UNIQUE INDEX payment_proof_operation ON public.payment_proofs(uploaded_by,operation_id)
  WHERE operation_id IS NOT NULL;
REVOKE INSERT,UPDATE,DELETE ON public.payment_proofs FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.can_view_payment_proofs(p_payment_id UUID)
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER STABLE SET search_path=public,pg_temp AS $$
  SELECT auth.uid() IS NOT NULL AND EXISTS(SELECT 1 FROM public.payments p WHERE p.id=p_payment_id
    AND public.is_tab_member(p.tab_id,auth.uid()) AND
    (COALESCE(p.payer_user_id,p.submitted_by)=auth.uid() OR p.recipient_user_id=auth.uid()));
$$;
REVOKE ALL ON FUNCTION public.can_view_payment_proofs(UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_view_payment_proofs(UUID) TO authenticated;
DROP POLICY IF EXISTS "Tab members can view payment proofs" ON public.payment_proofs;
CREATE POLICY "Payment parties can view proof revisions" ON public.payment_proofs FOR SELECT TO authenticated
  USING(public.can_view_payment_proofs(payment_id));
GRANT SELECT ON public.payment_proofs TO authenticated;

CREATE FUNCTION public.append_payment_proof_v1(p_operation_id UUID,p_command JSONB)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  v_actor UUID:=auth.uid();
  v_payment UUID:=(p_command->>'payment_id')::UUID;
  v_path TEXT:=COALESCE(p_command->>'proof_path','');
  v_reference TEXT:=nullif(trim(p_command->>'reference'),'');
  v_previous public.payment_proofs%ROWTYPE;
  v_result UUID;
BEGIN
  IF v_actor IS NULL OR NOT public.can_view_payment_proofs(v_payment) THEN
    RAISE EXCEPTION 'Only payment parties can attach proof' USING ERRCODE='42501';
  END IF;
  IF p_operation_id IS NULL OR (v_path='' AND v_reference IS NULL) OR length(v_reference)>200 THEN
    RAISE EXCEPTION 'Proof or reference and operation ID required' USING ERRCODE='22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('payment-proof:'||v_actor::TEXT||':'||p_operation_id::TEXT,0));
  SELECT * INTO v_previous FROM public.payment_proofs WHERE uploaded_by=v_actor AND operation_id=p_operation_id;
  IF FOUND THEN
    IF v_previous.payment_id IS DISTINCT FROM v_payment OR v_previous.file_url IS DISTINCT FROM v_path
       OR v_previous.reference IS DISTINCT FROM v_reference THEN
      RAISE EXCEPTION 'Proof operation reused with different content' USING ERRCODE='22023';
    END IF;
    RETURN v_previous.id;
  END IF;
  IF v_path<>'' AND (v_path NOT LIKE v_actor::TEXT||'/%' OR v_path ~ '(^|/)\.\.(/|$)' OR NOT EXISTS(
    SELECT 1 FROM storage.objects o WHERE o.bucket_id='payment-proofs' AND o.name=v_path)) THEN
    RAISE EXCEPTION 'Proof must reference your uploaded private object' USING ERRCODE='42501';
  END IF;
  INSERT INTO public.payment_proofs(payment_id,file_url,file_name,mime_type,operation_id,uploaded_by,reference)
    VALUES(v_payment,v_path,COALESCE(nullif(v_path,''),'Reference only'),
      CASE WHEN v_path='' THEN 'text/plain' ELSE 'image/*' END,p_operation_id,v_actor,v_reference)
    RETURNING id INTO v_result;
  RETURN v_result;
END; $$;
REVOKE ALL ON FUNCTION public.append_payment_proof_v1(UUID,JSONB) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.append_payment_proof_v1(UUID,JSONB) TO authenticated;

CREATE FUNCTION public.submit_payment_v2(p_operation_id UUID,p_command JSONB)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_payment UUID;
BEGIN
  v_payment:=public.execute_money_command_v1(p_operation_id,'payment',p_command);
  IF nullif(p_command->>'proof_path','') IS NOT NULL OR nullif(trim(p_command->>'reference'),'') IS NOT NULL THEN
    PERFORM public.append_payment_proof_v1(p_operation_id,jsonb_build_object('payment_id',v_payment,
      'proof_path',p_command->>'proof_path','reference',p_command->>'reference'));
  END IF;
  RETURN v_payment;
END; $$;
REVOKE ALL ON FUNCTION public.submit_payment_v2(UUID,JSONB) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.submit_payment_v2(UUID,JSONB) TO authenticated;

CREATE FUNCTION public.can_read_payment_proof_object(p_path TEXT)
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER STABLE SET search_path=public,pg_temp AS $$
  SELECT auth.uid() IS NOT NULL AND (
    p_path LIKE auth.uid()::TEXT||'/%' OR EXISTS(
      SELECT 1 FROM public.payment_proofs pp WHERE pp.file_url=p_path AND public.can_view_payment_proofs(pp.payment_id))
    OR EXISTS(SELECT 1 FROM public.transactions t WHERE t.receipt_url=p_path AND public.is_tab_member(t.tab_id,auth.uid())));
$$;
CREATE FUNCTION public.can_mutate_unreferenced_proof(p_path TEXT)
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER STABLE SET search_path=public,pg_temp AS $$
  SELECT auth.uid() IS NOT NULL AND p_path LIKE auth.uid()::TEXT||'/%'
    AND NOT EXISTS(SELECT 1 FROM public.payment_proofs pp WHERE pp.file_url=p_path)
    AND NOT EXISTS(SELECT 1 FROM public.transactions t WHERE t.receipt_url=p_path);
$$;
REVOKE ALL ON FUNCTION public.can_read_payment_proof_object(TEXT),public.can_mutate_unreferenced_proof(TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_read_payment_proof_object(TEXT),public.can_mutate_unreferenced_proof(TEXT) TO authenticated;
DO $$ BEGIN
  IF to_regclass('storage.objects') IS NOT NULL THEN
    DROP POLICY IF EXISTS "Authenticated users can view payment proofs" ON storage.objects;
    DROP POLICY IF EXISTS "Uploaders and tab counterparts can view payment proofs" ON storage.objects;
    DROP POLICY IF EXISTS "Users can update their own payment proofs" ON storage.objects;
    DROP POLICY IF EXISTS "Users can delete their own payment proofs" ON storage.objects;
    CREATE POLICY "Payment proof parties read exact objects" ON storage.objects FOR SELECT TO authenticated
      USING(bucket_id='payment-proofs' AND public.can_read_payment_proof_object(name));
    CREATE POLICY "Only unreferenced proof objects can change" ON storage.objects FOR UPDATE TO authenticated
      USING(bucket_id='payment-proofs' AND public.can_mutate_unreferenced_proof(name))
      WITH CHECK(bucket_id='payment-proofs' AND public.can_mutate_unreferenced_proof(name));
    CREATE POLICY "Only unreferenced proof objects can be deleted" ON storage.objects FOR DELETE TO authenticated
      USING(bucket_id='payment-proofs' AND public.can_mutate_unreferenced_proof(name));
  END IF;
END $$;
