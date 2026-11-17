BEGIN;
ALTER TABLE public.expense_change_requests ALTER COLUMN reviewer_id DROP NOT NULL;
ALTER TABLE public.expense_change_requests ADD COLUMN manual_contact_agreement boolean NOT NULL DEFAULT false;
ALTER TABLE public.expense_change_decisions DROP CONSTRAINT expense_change_decisions_pkey;
ALTER TABLE public.expense_change_decisions ADD PRIMARY KEY(change_id,actor_id);
CREATE TABLE public.expense_change_reviewers (
  change_id uuid NOT NULL REFERENCES public.expense_change_requests(id) ON DELETE RESTRICT,
  reviewer_id uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  PRIMARY KEY(change_id,reviewer_id)
);
ALTER TABLE public.expense_change_reviewers ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.expense_change_reviewers FROM PUBLIC,anon,authenticated;
INSERT INTO public.expense_change_reviewers SELECT id,reviewer_id FROM public.expense_change_requests WHERE reviewer_id IS NOT NULL;

CREATE FUNCTION public.expense_change_context_internal(p_id uuid,p_actor uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE expense public.transactions; tab public.tabs; n integer; contacts integer; payers integer; total numeric;
BEGIN
  SELECT * INTO expense FROM public.transactions WHERE id=p_id;
  IF expense.id IS NULL OR NOT public.is_tab_member(expense.tab_id,p_actor) OR NOT EXISTS(
    SELECT 1 FROM public.transaction_participants WHERE transaction_id=p_id AND user_id=p_actor) THEN RETURN NULL; END IF;
  SELECT * INTO tab FROM public.tabs WHERE id=expense.tab_id;
  SELECT count(*),count(*) FILTER(WHERE contact_id IS NOT NULL),
    count(*) FILTER(WHERE participant_role='payer'),sum(share_amount_centavos)
    INTO n,contacts,payers,total FROM public.transaction_participants WHERE transaction_id=p_id;
  IF n NOT BETWEEN 1 AND 100 OR payers<>1 OR total<>expense.total_amount_centavos
    OR expense.total_amount_centavos NOT BETWEEN 1 AND 99999999999
    OR expense.status NOT IN ('pending','acknowledged')
    OR EXISTS(SELECT 1 FROM public.transaction_participants WHERE transaction_id=p_id
      AND ((user_id IS NULL)=(contact_id IS NULL) OR (user_id IS NOT NULL AND NOT public.is_tab_member(expense.tab_id,user_id))))
    OR EXISTS(SELECT 1 FROM public.expense_change_outputs WHERE transaction_id=p_id AND role='reversal') THEN RETURN NULL; END IF;
  IF contacts>0 THEN
    IF tab.tab_type<>'individual' OR contacts<>1 OR n<>2 OR NOT EXISTS(
      SELECT 1 FROM public.transaction_participants s JOIN public.contacts c ON c.id=s.contact_id
      WHERE s.transaction_id=p_id AND c.owner_user_id=p_actor AND c.claimed_user_id IS NULL) THEN RETURN NULL; END IF;
  ELSIF tab.tab_type IN ('individual','shared_couple') THEN
    IF n<>2 OR tab.user_a IS NULL OR tab.user_b IS NULL OR
      (SELECT count(*) FROM public.transaction_participants WHERE transaction_id=p_id AND user_id IN(tab.user_a,tab.user_b))<>2 THEN RETURN NULL; END IF;
  ELSIF tab.tab_type<>'group' THEN RETURN NULL;
  END IF;
  RETURN jsonb_build_object('can_request',NOT EXISTS(SELECT 1 FROM public.expense_change_results WHERE transaction_id=p_id),
    'manual_contact',contacts=1);
END $$;
REVOKE ALL ON FUNCTION public.expense_change_context_internal(uuid,uuid) FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.apply_expense_change_internal(p_change_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE change public.expense_change_requests; expense public.transactions;
  payer public.transaction_participants; party public.transaction_participants;
  reversed uuid; first_reversal uuid; replacement uuid; reversals uuid[]:='{}';
  shares jsonb:='[]'; payer_share bigint; new_share bigint;
BEGIN
  SELECT * INTO STRICT change FROM public.expense_change_requests WHERE id=p_change_id;
  PERFORM pg_advisory_xact_lock(hashtextextended(change.transaction_id::text,1));
  IF EXISTS(SELECT 1 FROM public.expense_change_results WHERE transaction_id=change.transaction_id) THEN
    RAISE EXCEPTION 'Expense already revised' USING ERRCODE='22023'; END IF;
  IF EXISTS(SELECT 1 FROM public.expense_change_reviewers r WHERE r.change_id=p_change_id AND NOT EXISTS(
    SELECT 1 FROM public.expense_change_decisions d WHERE d.change_id=r.change_id AND d.actor_id=r.reviewer_id AND d.accepted))
    OR EXISTS(SELECT 1 FROM public.expense_change_decisions WHERE change_id=p_change_id AND NOT accepted) THEN
    RAISE EXCEPTION 'All registered participants must agree' USING ERRCODE='42501'; END IF;
  SELECT * INTO expense FROM public.transactions WHERE id=change.transaction_id FOR SHARE;
  PERFORM 1 FROM public.transaction_participants WHERE transaction_id=expense.id FOR SHARE;
  IF change.original_snapshot IS DISTINCT FROM jsonb_build_object('expense',to_jsonb(expense),'shares',
    (SELECT jsonb_agg(to_jsonb(s) ORDER BY s.id) FROM public.transaction_participants s WHERE transaction_id=expense.id)) THEN
    RAISE EXCEPTION 'Original expense changed; request a fresh review' USING ERRCODE='22023'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(expense.tab_id::text,0));
  SELECT * INTO STRICT payer FROM public.transaction_participants WHERE transaction_id=expense.id AND participant_role='payer';
  payer_share:=change.new_total_centavos;
  FOR party IN SELECT * FROM public.transaction_participants WHERE transaction_id=expense.id AND id<>payer.id ORDER BY id LOOP
    IF party.share_amount_centavos>0 THEN
      reversed:=public.create_expense_atomic(expense.tab_id,'Reversal: '||expense.description,expense.category,
        party.share_amount_centavos,COALESCE(party.user_id,party.contact_id),jsonb_build_array(
          jsonb_build_object('user_id',party.user_id,'contact_id',party.contact_id,'participant_role','payer','share_amount_centavos',0),
          jsonb_build_object('user_id',payer.user_id,'contact_id',payer.contact_id,'participant_role','debtor','share_amount_centavos',party.share_amount_centavos)),NULL,NULL);
      reversals:=array_append(reversals,reversed);
      IF first_reversal IS NULL THEN first_reversal:=reversed; END IF;
    END IF;
    IF change.kind='correct' THEN
      new_share:=trunc(change.new_total_centavos::numeric*party.share_amount_centavos/expense.total_amount_centavos)::bigint;
      payer_share:=payer_share-new_share;
      shares:=shares||jsonb_build_array(jsonb_build_object('user_id',party.user_id,'contact_id',party.contact_id,
        'participant_role',party.participant_role,'share_amount_centavos',new_share));
    END IF;
  END LOOP;
  IF change.kind='correct' THEN
    shares:=shares||jsonb_build_array(jsonb_build_object('user_id',payer.user_id,'contact_id',payer.contact_id,'participant_role','payer','share_amount_centavos',payer_share));
    replacement:=public.create_expense_atomic(expense.tab_id,expense.description,expense.category,change.new_total_centavos,
      COALESCE(payer.user_id,payer.contact_id),shares,expense.due_date,expense.receipt_url);
  END IF;
  INSERT INTO public.expense_change_results(change_id,transaction_id,reversal_id,replacement_id)
    VALUES(change.id,expense.id,first_reversal,replacement);
  INSERT INTO public.expense_change_outputs(transaction_id,change_id,role)
    SELECT value,change.id,'reversal' FROM unnest(reversals) value ON CONFLICT DO NOTHING;
  INSERT INTO public.activity_logs(actor_user_id,tab_id,transaction_id,event_type,metadata)
    VALUES(auth.uid(),expense.tab_id,expense.id,'EXPENSE_CHANGE_APPLIED',jsonb_build_object('change_id',change.id,
      'kind',change.kind,'reason',change.reason,'manual_contact_agreement',change.manual_contact_agreement,
      'reversal_ids',to_jsonb(reversals),'replacement_id',replacement));
  INSERT INTO public.notifications(recipient_user_id,notification_type,related_tab_id,related_transaction_id,title,body)
    SELECT DISTINCT s.user_id,'amount_changed',expense.tab_id,expense.id,'Expense change accepted',
      'Your shared history now includes the agreed revision.' FROM public.transaction_participants s
      WHERE s.transaction_id=expense.id AND s.user_id IS NOT NULL AND s.user_id<>auth.uid();
END $$;
REVOKE ALL ON FUNCTION public.apply_expense_change_internal(uuid) FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.request_expense_change_v2(p_operation_id uuid,p_transaction_id uuid,p_kind text,
  p_new_total bigint,p_reason text,p_expected_actor uuid,p_contact_agreement boolean DEFAULT false)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor uuid:=auth.uid(); expense public.transactions; context jsonb;
  previous public.financial_operations; result uuid; reviewers uuid[]; command jsonb;
BEGIN
  IF actor IS NULL OR actor IS DISTINCT FROM p_expected_actor THEN RAISE EXCEPTION 'Initiating account required' USING ERRCODE='42501'; END IF;
  IF p_operation_id IS NULL OR p_kind IS NULL OR p_kind NOT IN ('correct','cancel') OR p_contact_agreement IS NULL
    OR p_reason IS NULL OR length(trim(p_reason)) NOT BETWEEN 1 AND 500 THEN
    RAISE EXCEPTION 'Valid change identity, kind and reason required' USING ERRCODE='22023'; END IF;
  command:=jsonb_build_object('transaction_id',p_transaction_id,'kind',p_kind,'new_total',p_new_total,'reason',p_reason);
  IF p_contact_agreement THEN command:=command||jsonb_build_object('contact_agreement',true); END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':'||p_operation_id::text,0));
  SELECT * INTO previous FROM public.financial_operations WHERE actor_id=actor AND operation_id=p_operation_id;
  IF FOUND THEN
    IF previous.command_kind<>'expense_change' OR previous.command IS DISTINCT FROM command THEN
      RAISE EXCEPTION 'Operation ID reused with different command' USING ERRCODE='22023'; END IF;
    RETURN previous.result_id;
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(p_transaction_id::text,1));
  SELECT * INTO expense FROM public.transactions WHERE id=p_transaction_id;
  IF expense.id IS NULL OR NOT public.is_tab_member(expense.tab_id,actor) OR NOT EXISTS(
    SELECT 1 FROM public.transaction_participants WHERE transaction_id=expense.id AND user_id=actor) THEN
    RAISE EXCEPTION 'Expense participant required' USING ERRCODE='42501'; END IF;
  context:=public.expense_change_context_internal(expense.id,actor);
  IF context IS NULL OR NOT (context->>'can_request')::boolean THEN RAISE EXCEPTION 'Expense not eligible' USING ERRCODE='22023'; END IF;
  IF (context->>'manual_contact')::boolean IS DISTINCT FROM p_contact_agreement THEN
    RAISE EXCEPTION 'Manual contact changes require explicit outside-app agreement' USING ERRCODE='22023'; END IF;
  IF (p_kind='cancel' AND p_new_total IS NOT NULL) OR (p_kind='correct' AND
    (p_new_total IS NULL OR p_new_total NOT BETWEEN 1 AND 99999999999 OR p_new_total=expense.total_amount_centavos)) THEN
    RAISE EXCEPTION 'Different positive total or cancellation required' USING ERRCODE='22023'; END IF;
  SELECT COALESCE(array_agg(user_id ORDER BY user_id),'{}') INTO reviewers FROM public.transaction_participants
    WHERE transaction_id=expense.id AND user_id IS NOT NULL AND user_id<>actor;
  INSERT INTO public.expense_change_requests(transaction_id,requested_by,reviewer_id,kind,new_total_centavos,reason,original_snapshot,manual_contact_agreement)
    VALUES(expense.id,actor,reviewers[1],p_kind,p_new_total,trim(p_reason),jsonb_build_object('expense',to_jsonb(expense),'shares',
      (SELECT jsonb_agg(to_jsonb(s) ORDER BY s.id) FROM public.transaction_participants s WHERE transaction_id=expense.id)),p_contact_agreement) RETURNING id INTO result;
  INSERT INTO public.expense_change_reviewers SELECT result,value FROM unnest(reviewers) value;
  INSERT INTO public.financial_operations VALUES(actor,p_operation_id,'expense_change',command,result,now());
  IF cardinality(reviewers)=0 THEN
    INSERT INTO public.expense_change_decisions(change_id,actor_id,accepted) VALUES(result,actor,true);
    PERFORM public.apply_expense_change_internal(result);
  ELSE
    INSERT INTO public.notifications(recipient_user_id,notification_type,related_tab_id,related_transaction_id,title,body)
      SELECT value,'amount_proposed',expense.tab_id,expense.id,'Expense change requested','Review a proposed change in your shared tab.' FROM unnest(reviewers) value;
  END IF;
  RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.request_expense_change_v2(uuid,uuid,text,bigint,text,uuid,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.request_expense_change_v2(uuid,uuid,text,bigint,text,uuid,boolean) TO authenticated;
CREATE OR REPLACE FUNCTION public.request_expense_change_v1(p_operation_id uuid,p_transaction_id uuid,p_kind text,p_new_total bigint,p_reason text,p_expected_actor uuid)
RETURNS uuid LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
  SELECT public.request_expense_change_v2(p_operation_id,p_transaction_id,p_kind,p_new_total,p_reason,p_expected_actor,false);
$$;

CREATE OR REPLACE FUNCTION public.decide_expense_change_v1(p_change_id uuid,p_accept boolean,p_expected_actor uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor uuid:=auth.uid(); change public.expense_change_requests; previous public.expense_change_decisions;
BEGIN
  SELECT * INTO change FROM public.expense_change_requests WHERE id=p_change_id;
  IF actor IS NULL OR actor IS DISTINCT FROM p_expected_actor OR change.id IS NULL OR NOT EXISTS(
    SELECT 1 FROM public.expense_change_reviewers WHERE change_id=p_change_id AND reviewer_id=actor)
    OR NOT public.is_tab_member((SELECT tab_id FROM public.transactions WHERE id=change.transaction_id),actor) THEN
    RAISE EXCEPTION 'Registered reviewer required' USING ERRCODE='42501'; END IF;
  IF p_accept IS NULL THEN RAISE EXCEPTION 'Decision required' USING ERRCODE='22023'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(change.transaction_id::text,1));
  SELECT * INTO previous FROM public.expense_change_decisions WHERE change_id=p_change_id AND actor_id=actor;
  IF FOUND THEN
    IF previous.accepted IS DISTINCT FROM p_accept THEN RAISE EXCEPTION 'Decision already recorded' USING ERRCODE='22023'; END IF;
    RETURN change.id;
  END IF;
  IF EXISTS(SELECT 1 FROM public.expense_change_results WHERE transaction_id=change.transaction_id) OR
    EXISTS(SELECT 1 FROM public.expense_change_decisions WHERE change_id=p_change_id AND NOT accepted) THEN
    RAISE EXCEPTION 'Another revision or rejection is final' USING ERRCODE='22023'; END IF;
  INSERT INTO public.expense_change_decisions VALUES(change.id,actor,p_accept,now());
  IF p_accept AND NOT EXISTS(SELECT 1 FROM public.expense_change_reviewers r WHERE r.change_id=p_change_id AND NOT EXISTS(
    SELECT 1 FROM public.expense_change_decisions d WHERE d.change_id=r.change_id AND d.actor_id=r.reviewer_id AND d.accepted)) THEN
    PERFORM public.apply_expense_change_internal(change.id);
  END IF;
  RETURN change.id;
END $$;

CREATE OR REPLACE FUNCTION public.list_expense_changes_v1(p_transaction_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor uuid:=auth.uid(); changes jsonb; context jsonb;
BEGIN
  IF actor IS NULL OR NOT EXISTS(SELECT 1 FROM public.transaction_participants s JOIN public.transactions t ON t.id=s.transaction_id
    WHERE t.id=p_transaction_id AND s.user_id=actor AND public.is_tab_member(t.tab_id,actor)) THEN
    RAISE EXCEPTION 'Expense participant required' USING ERRCODE='42501'; END IF;
  context:=public.expense_change_context_internal(p_transaction_id,actor);
  SELECT COALESCE(jsonb_agg(value ORDER BY created_at,id),'[]') INTO changes FROM (
    SELECT r.created_at,r.id,jsonb_build_object('id',r.id,'transaction_id',r.transaction_id,'requested_by',r.requested_by,
      'reviewer_id',r.reviewer_id,'kind',r.kind,'new_total_centavos',r.new_total_centavos,'reason',r.reason,'created_at',r.created_at,
      'manual_contact_agreement',r.manual_contact_agreement,
      'required_reviewers',(SELECT count(*) FROM public.expense_change_reviewers WHERE change_id=r.id),
      'accepted_reviewers',(SELECT count(*) FROM public.expense_change_reviewers v JOIN public.expense_change_decisions d ON d.change_id=v.change_id AND d.actor_id=v.reviewer_id WHERE v.change_id=r.id AND d.accepted),
      'can_review',o.change_id IS NULL AND NOT EXISTS(SELECT 1 FROM public.expense_change_results WHERE transaction_id=r.transaction_id)
        AND NOT EXISTS(SELECT 1 FROM public.expense_change_decisions WHERE change_id=r.id AND NOT accepted)
        AND EXISTS(SELECT 1 FROM public.expense_change_reviewers WHERE change_id=r.id AND reviewer_id=actor)
        AND NOT EXISTS(SELECT 1 FROM public.expense_change_decisions WHERE change_id=r.id AND actor_id=actor),
      'status',CASE WHEN o.change_id IS NOT NULL THEN 'applied' WHEN EXISTS(SELECT 1 FROM public.expense_change_decisions WHERE change_id=r.id AND NOT accepted) THEN 'rejected'
        WHEN EXISTS(SELECT 1 FROM public.expense_change_results WHERE transaction_id=r.transaction_id) THEN 'superseded' ELSE 'pending' END,
      'reversal_id',o.reversal_id,'replacement_id',o.replacement_id,
      'reversal_ids',(SELECT COALESCE(jsonb_agg(transaction_id ORDER BY transaction_id),'[]') FROM public.expense_change_outputs WHERE change_id=r.id AND role='reversal')) value
    FROM public.expense_change_requests r LEFT JOIN public.expense_change_results o ON o.change_id=r.id WHERE r.transaction_id=p_transaction_id
  ) items;
  RETURN jsonb_build_object('account_id',actor,'transaction_id',p_transaction_id,'changes',changes,
    'can_request',COALESCE((context->>'can_request')::boolean,false),'manual_contact',COALESCE((context->>'manual_contact')::boolean,false));
END $$;
NOTIFY pgrst,'reload schema';
COMMIT;
