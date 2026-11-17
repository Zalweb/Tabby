BEGIN;
CREATE TABLE public.m2_feature_flags(feature text PRIMARY KEY, enabled boolean NOT NULL DEFAULT false);
INSERT INTO public.m2_feature_flags(feature) VALUES('custom_splits'),('recurring'),('contact_claiming'),('expense_review');
ALTER TABLE public.m2_feature_flags ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.m2_feature_flags FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.require_m2_v1(p_feature text,p_operation uuid,p_command jsonb,p_kind text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor uuid:=auth.uid(); prior public.financial_operations;
BEGIN
  PERFORM public.tabby_pre_request();
  IF actor IS NULL OR actor IS DISTINCT FROM (p_command->>'p_expected_actor')::uuid THEN
    RAISE EXCEPTION 'Account changed' USING ERRCODE='42501'; END IF;
  IF NOT coalesce((SELECT enabled FROM public.m2_feature_flags WHERE feature=p_feature),false) THEN
    RAISE EXCEPTION 'Feature awaiting acceptance' USING ERRCODE='42501'; END IF;
  IF p_operation IS NULL OR p_command IS NULL OR jsonb_typeof(p_command)<>'object' THEN
    RAISE EXCEPTION 'Operation and command required' USING ERRCODE='22023'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':'||p_operation::text,0));
  SELECT * INTO prior FROM public.financial_operations WHERE actor_id=actor AND operation_id=p_operation;
  IF FOUND THEN
    IF prior.command_kind<>p_kind OR prior.command IS DISTINCT FROM p_command THEN
      RAISE EXCEPTION 'Operation payload conflict' USING ERRCODE='22023'; END IF;
    RETURN prior.result_id;
  END IF;
  RETURN NULL;
END $$;
CREATE FUNCTION public.record_m2_v1(p_operation uuid,p_kind text,p_command jsonb,p_result uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  INSERT INTO public.financial_operations(actor_id,operation_id,command_kind,command,result_id)
    VALUES(auth.uid(),p_operation,p_kind,p_command,p_result);
  RETURN p_result;
END $$;
REVOKE ALL ON FUNCTION public.require_m2_v1(text,uuid,jsonb,text),public.record_m2_v1(uuid,text,jsonb,uuid) FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.allocate_custom_split_v1(p_split jsonb,p_payer uuid) RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog,public AS $$
DECLARE base bigint; tax_rate integer; fee_rate integer; tax bigint; fee bigint; n integer; parts jsonb;
BEGIN
  IF p_split IS NULL OR jsonb_typeof(p_split)<>'object' OR
    p_split-ARRAY['base_centavos','tax_basis_points','service_basis_points','base_shares']<>'{}'::jsonb OR
    coalesce(p_split->>'base_centavos','')!~'^[0-9]{1,11}$' OR
    coalesce(p_split->>'tax_basis_points','')!~'^[0-9]{1,5}$' OR
    coalesce(p_split->>'service_basis_points','')!~'^[0-9]{1,5}$' OR
    jsonb_typeof(p_split->'base_shares') IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'Invalid split' USING ERRCODE='22023'; END IF;
  base:=(p_split->>'base_centavos')::bigint; tax_rate:=(p_split->>'tax_basis_points')::integer;
  fee_rate:=(p_split->>'service_basis_points')::integer; n:=jsonb_array_length(p_split->'base_shares');
  IF base NOT BETWEEN 1 AND 99999999999 OR tax_rate NOT BETWEEN 0 AND 10000 OR fee_rate NOT BETWEEN 0 AND 10000 OR n NOT BETWEEN 1 AND 100 THEN
    RAISE EXCEPTION 'Split outside supported limits' USING ERRCODE='22023'; END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_split->'base_shares') b WHERE
    jsonb_typeof(b)<>'object' OR b-ARRAY['party','amount']<>'{}'::jsonb OR
    coalesce(b->>'amount','')!~'^[0-9]{1,11}$' OR
    coalesce(b->'party'->>'kind','') NOT IN ('user','contact') OR
    coalesce(b->'party'->>'id','')!~'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') OR
    (SELECT count(DISTINCT b->'party'->>'id') FROM jsonb_array_elements(p_split->'base_shares') b)<>n OR
    (SELECT sum((b->>'amount')::bigint) FROM jsonb_array_elements(p_split->'base_shares') b)<>base OR
    NOT EXISTS(SELECT 1 FROM jsonb_array_elements(p_split->'base_shares') b WHERE b->'party'->>'id'=p_payer::text) THEN
    RAISE EXCEPTION 'Invalid or duplicate parties/base shares' USING ERRCODE='22023'; END IF;
  tax:=round(base::numeric*tax_rate/10000)::bigint; fee:=round(base::numeric*fee_rate/10000)::bigint;
  IF base+tax+fee>99999999999 THEN RAISE EXCEPTION 'Total outside supported limit' USING ERRCODE='22023'; END IF;
  WITH weights AS (SELECT b->'party' party,(b->>'amount')::bigint amount,
    b->'party'->>'kind'||':'||(b->'party'->>'id') identity FROM jsonb_array_elements(p_split->'base_shares') b),
  floors AS (SELECT *,floor(tax::numeric*amount/base)::bigint t,floor(fee::numeric*amount/base)::bigint f,
    mod(tax::numeric*amount,base) tr,mod(fee::numeric*amount,base) fr FROM weights),
  ranked AS (SELECT *,row_number() OVER(ORDER BY tr DESC,identity) tn,row_number() OVER(ORDER BY fr DESC,identity) fn,
    tax-sum(t) OVER() tl,fee-sum(f) OVER() fl FROM floors)
  SELECT jsonb_agg(jsonb_build_object(CASE WHEN party->>'kind'='user' THEN 'user_id' ELSE 'contact_id' END,
    party->>'id','participant_role',CASE WHEN party->>'id'=p_payer::text THEN 'payer' ELSE 'debtor' END,
    'share_amount_centavos',amount+t+f+CASE WHEN tn<=tl THEN 1 ELSE 0 END+CASE WHEN fn<=fl THEN 1 ELSE 0 END,
    'acknowledged',false) ORDER BY identity) INTO parts FROM ranked;
  RETURN jsonb_build_object('base_centavos',base,'tax_centavos',tax,'service_centavos',fee,
    'total_centavos',base+tax+fee,'participants',parts);
END $$;
REVOKE ALL ON FUNCTION public.allocate_custom_split_v1(jsonb,uuid) FROM PUBLIC,anon,authenticated;

CREATE TABLE public.expense_split_details(transaction_id uuid PRIMARY KEY REFERENCES public.transactions(id) ON DELETE RESTRICT,
  breakdown jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now());
ALTER TABLE public.expense_split_details ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.expense_split_details FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.expense_split_details TO authenticated;
CREATE FUNCTION public.can_read_expense_split_v1(p_transaction uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
  SELECT auth.uid() IS NOT NULL AND EXISTS(SELECT 1 FROM public.transactions t
    WHERE t.id=p_transaction AND public.is_tab_member(t.tab_id,auth.uid()));
$$;
REVOKE ALL ON FUNCTION public.can_read_expense_split_v1(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_read_expense_split_v1(uuid) TO authenticated;
CREATE POLICY split_participant_read ON public.expense_split_details FOR SELECT TO authenticated USING(
  public.can_read_expense_split_v1(transaction_id));
CREATE POLICY tabby_active_actor ON public.expense_split_details AS RESTRICTIVE FOR ALL TO authenticated
  USING((SELECT public.account_is_active_v1())) WITH CHECK((SELECT public.account_is_active_v1()));

CREATE FUNCTION public.validate_expense_roster_v2(p_tab uuid,p_parts jsonb,p_actor uuid) RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE tab public.tabs; part jsonb; u uuid; c uuid;
BEGIN
  SELECT * INTO tab FROM public.tabs WHERE id=p_tab;
  IF tab.id IS NULL OR tab.status<>'active' OR NOT public.is_tab_member(p_tab,p_actor) OR
    NOT EXISTS(SELECT 1 FROM public.users WHERE id=p_actor AND anonymized_at IS NULL) OR
    (tab.group_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.group_members
      WHERE group_id=tab.group_id AND user_id=p_actor AND status='active')) THEN
    RAISE EXCEPTION 'Active tab membership required' USING ERRCODE='42501'; END IF;
  IF jsonb_typeof(p_parts) IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Explicit shares required' USING ERRCODE='22023'; END IF;
  FOR part IN SELECT value FROM jsonb_array_elements(p_parts) LOOP
    u:=nullif(part->>'user_id','')::uuid;c:=nullif(part->>'contact_id','')::uuid;
    IF (u IS NULL)=(c IS NULL) THEN RAISE EXCEPTION 'One party identity required' USING ERRCODE='22023'; END IF;
    IF u IS NOT NULL AND (NOT public.is_tab_member(p_tab,u) OR
      NOT EXISTS(SELECT 1 FROM public.users WHERE id=u AND anonymized_at IS NULL) OR
      (tab.group_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.group_members WHERE group_id=tab.group_id AND user_id=u AND status='active'))) THEN
      RAISE EXCEPTION 'Participant no longer active in this group' USING ERRCODE='42501'; END IF;
    IF c IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.contacts contact JOIN public.tab_members m ON m.contact_id=contact.id
      WHERE contact.id=c AND contact.owner_user_id=p_actor AND contact.claim_status='unclaimed'
        AND m.tab_id=p_tab AND tab.tab_type='individual' AND tab.group_id IS NULL) THEN
      RAISE EXCEPTION 'Owned unclaimed contact required' USING ERRCODE='42501'; END IF;
  END LOOP;
END $$;
REVOKE ALL ON FUNCTION public.validate_expense_roster_v2(uuid,jsonb,uuid) FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.create_expense_v3(p_operation_id uuid,p_command jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE result uuid; split jsonb;
BEGIN
  result:=public.require_m2_v1('custom_splits',p_operation_id,p_command,'m2_custom_split');
  IF result IS NOT NULL THEN RETURN result; END IF;
  IF NOT public.is_tab_member((p_command->>'p_tab_id')::uuid,auth.uid()) THEN
    RAISE EXCEPTION 'Tab membership required' USING ERRCODE='42501'; END IF;
  IF p_command-ARRAY['p_expected_actor','p_tab_id','p_description','p_category','p_total_amount_centavos',
    'p_paid_by_user_id','p_participants','p_due_date','p_receipt_url','split']<>'{}'::jsonb THEN
    RAISE EXCEPTION 'Unsupported split fields' USING ERRCODE='22023'; END IF;
  split:=public.allocate_custom_split_v1(p_command->'split',(p_command->>'p_paid_by_user_id')::uuid);
  PERFORM public.validate_expense_roster_v2((p_command->>'p_tab_id')::uuid,split->'participants',auth.uid());
  IF coalesce(p_command->>'p_total_amount_centavos','')!~'^[0-9]{1,11}$' OR
    (p_command->>'p_total_amount_centavos')::bigint<>(split->>'total_centavos')::bigint OR
    jsonb_typeof(p_command->'p_participants') IS DISTINCT FROM 'array' OR
    jsonb_array_length(p_command->'p_participants')<>jsonb_array_length(split->'participants') OR
    EXISTS(SELECT 1 FROM jsonb_array_elements(split->'participants') expected WHERE
      (SELECT count(*) FROM jsonb_array_elements(p_command->'p_participants') actual WHERE actual=expected)<>1) THEN
    RAISE EXCEPTION 'Submitted allocation differs from calculated total' USING ERRCODE='22023'; END IF;
  result:=public.create_expense_atomic((p_command->>'p_tab_id')::uuid,p_command->>'p_description',
    p_command->>'p_category',(split->>'total_centavos')::bigint,(p_command->>'p_paid_by_user_id')::uuid,
    split->'participants',(p_command->>'p_due_date')::date,p_command->>'p_receipt_url');
  INSERT INTO public.expense_split_details VALUES(result,(p_command->'split')||split,now());
  RETURN public.record_m2_v1(p_operation_id,'m2_custom_split',p_command,result);
END $$;
REVOKE ALL ON FUNCTION public.create_expense_v3(uuid,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_expense_v3(uuid,jsonb) TO authenticated;

-- Fresh M1 writes also require current roster; historical rows stay intact.
CREATE OR REPLACE FUNCTION public.execute_money_command_v1(
    p_operation_id UUID, p_kind TEXT, p_command JSONB
) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
    v_actor UUID := auth.uid();
    v_original public.financial_operations%ROWTYPE;
    v_result UUID;
BEGIN
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;
    IF p_operation_id IS NULL OR p_command IS NULL
       OR jsonb_typeof(p_command) <> 'object' THEN
        RAISE EXCEPTION 'Operation ID and command object required' USING ERRCODE = '22023';
    END IF;
    IF NOT public.is_tab_member((p_command->>'p_tab_id')::UUID, v_actor) THEN
        RAISE EXCEPTION 'Tab membership required' USING ERRCODE = '42501';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtextextended(v_actor::TEXT || ':' || p_operation_id::TEXT, 0));
    SELECT * INTO v_original FROM public.financial_operations
        WHERE actor_id = v_actor AND operation_id = p_operation_id;
    IF FOUND THEN
        IF v_original.command_kind IS DISTINCT FROM p_kind
           OR v_original.command IS DISTINCT FROM p_command THEN
            RAISE EXCEPTION 'Operation ID reused with a different command' USING ERRCODE = '22023';
        END IF;
        RETURN v_original.result_id;
    END IF;
    IF p_kind = 'expense' THEN
        PERFORM public.validate_expense_roster_v2((p_command->>'p_tab_id')::uuid,p_command->'p_participants',v_actor);
        v_result := public.create_expense_atomic(
            (p_command->>'p_tab_id')::UUID, p_command->>'p_description',
            p_command->>'p_category', (p_command->>'p_total_amount_centavos')::BIGINT,
            (p_command->>'p_paid_by_user_id')::UUID, p_command->'p_participants',
            (p_command->>'p_due_date')::DATE, p_command->>'p_receipt_url');
    ELSIF p_kind = 'payment' THEN
        v_result := public.submit_payment(
            (p_command->>'p_tab_id')::UUID, (p_command->>'p_submitted_by_user_id')::UUID,
            (p_command->>'p_recipient_user_id')::UUID, (p_command->>'p_amount_centavos')::BIGINT,
            p_command->>'p_payment_method', p_command->>'p_note');
    ELSE
        RAISE EXCEPTION 'Unsupported money command' USING ERRCODE = '22023';
    END IF;
    INSERT INTO public.financial_operations(actor_id, operation_id, command_kind, command, result_id)
        VALUES (v_actor, p_operation_id, p_kind, p_command, v_result);
    RETURN v_result;
END;
$$;
COMMIT;
