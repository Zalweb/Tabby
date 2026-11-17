BEGIN;
CREATE TABLE public.expense_change_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  transaction_id uuid NOT NULL REFERENCES public.transactions(id) ON DELETE RESTRICT,
  requested_by uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  reviewer_id uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  kind text NOT NULL CHECK (kind IN ('correct','cancel')),
  new_total_centavos bigint,
  reason text NOT NULL CHECK (length(trim(reason)) BETWEEN 1 AND 500),
  original_snapshot jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (requested_by <> reviewer_id),
  CHECK ((kind='cancel' AND new_total_centavos IS NULL) OR
    (kind='correct' AND new_total_centavos BETWEEN 1 AND 99999999999))
);
CREATE INDEX ON public.expense_change_requests(transaction_id,created_at,id);
CREATE TABLE public.expense_change_decisions (
  change_id uuid PRIMARY KEY REFERENCES public.expense_change_requests(id) ON DELETE RESTRICT,
  actor_id uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  accepted boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.expense_change_results (
  change_id uuid PRIMARY KEY REFERENCES public.expense_change_requests(id) ON DELETE RESTRICT,
  transaction_id uuid NOT NULL UNIQUE REFERENCES public.transactions(id) ON DELETE RESTRICT,
  reversal_id uuid REFERENCES public.transactions(id) ON DELETE RESTRICT,
  replacement_id uuid REFERENCES public.transactions(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.expense_change_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expense_change_decisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expense_change_results ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.expense_change_requests,public.expense_change_decisions,
  public.expense_change_results FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.request_expense_change_v1(
  p_operation_id uuid,p_transaction_id uuid,p_kind text,p_new_total bigint,p_reason text,p_expected_actor uuid
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor uuid:=auth.uid(); expense public.transactions;
  roster integer; reviewer uuid; result uuid; previous public.financial_operations;
  command jsonb:=jsonb_build_object('transaction_id',p_transaction_id,'kind',p_kind,
    'new_total',p_new_total,'reason',p_reason);
BEGIN
  IF actor IS NULL OR actor IS DISTINCT FROM p_expected_actor THEN RAISE EXCEPTION 'Initiating account required' USING ERRCODE='42501'; END IF;
  IF p_operation_id IS NULL OR p_kind IS NULL OR p_kind NOT IN ('correct','cancel')
    OR p_reason IS NULL OR length(trim(p_reason)) NOT BETWEEN 1 AND 500 THEN
    RAISE EXCEPTION 'Change identity, kind and reason required' USING ERRCODE='22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':'||p_operation_id::text,0));
  SELECT * INTO previous FROM public.financial_operations WHERE actor_id=actor AND operation_id=p_operation_id;
  IF FOUND THEN
    IF previous.command_kind<>'expense_change' OR previous.command IS DISTINCT FROM command THEN
      RAISE EXCEPTION 'Operation ID reused with a different command' USING ERRCODE='22023';
    END IF;
    RETURN previous.result_id;
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(p_transaction_id::text,1));
  SELECT * INTO expense FROM public.transactions WHERE id=p_transaction_id;
  IF NOT FOUND OR NOT public.is_tab_member(expense.tab_id,actor) OR NOT EXISTS (
    SELECT 1 FROM public.transaction_participants WHERE transaction_id=expense.id AND user_id=actor)
    OR NOT EXISTS(SELECT 1 FROM public.tabs WHERE id=expense.tab_id AND tab_type='individual') THEN
    RAISE EXCEPTION 'Expense participant required' USING ERRCODE='42501';
  END IF;
  SELECT count(*), min(user_id::text) FILTER (WHERE user_id<>actor)::uuid
    INTO roster,reviewer FROM public.transaction_participants WHERE transaction_id=expense.id;
  IF roster<>2 OR reviewer IS NULL OR EXISTS(SELECT 1 FROM public.transaction_participants
    WHERE transaction_id=expense.id AND (contact_id IS NOT NULL OR user_id IS NULL))
    OR (SELECT count(*) FROM public.transaction_participants WHERE transaction_id=expense.id AND participant_role='payer')<>1
    OR (SELECT sum(share_amount_centavos) FROM public.transaction_participants WHERE transaction_id=expense.id)<>expense.total_amount_centavos
    OR expense.status NOT IN ('pending','acknowledged')
    OR expense.total_amount_centavos>99999999999
    OR EXISTS(SELECT 1 FROM public.expense_change_results WHERE reversal_id=expense.id) THEN
    RAISE EXCEPTION 'This expense cannot be changed by this workflow' USING ERRCODE='22023';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.tabs WHERE id=expense.tab_id
    AND LEAST(user_a,user_b)=LEAST(actor,reviewer) AND GREATEST(user_a,user_b)=GREATEST(actor,reviewer)
    AND user_a IS NOT NULL AND user_b IS NOT NULL) THEN
    RAISE EXCEPTION 'Expense must match the registered bilateral pair' USING ERRCODE='22023';
  END IF;
  IF (p_kind='cancel' AND p_new_total IS NOT NULL) OR
    (p_kind='correct' AND (p_new_total IS NULL OR p_new_total NOT BETWEEN 1 AND 99999999999
      OR p_new_total=expense.total_amount_centavos)) THEN
    RAISE EXCEPTION 'A different positive total or cancellation is required' USING ERRCODE='22023';
  END IF;
  IF EXISTS(SELECT 1 FROM public.expense_change_results WHERE transaction_id=expense.id) THEN
    RAISE EXCEPTION 'Expense already revised; use its replacement' USING ERRCODE='22023';
  END IF;
  INSERT INTO public.expense_change_requests(transaction_id,requested_by,reviewer_id,kind,new_total_centavos,reason,original_snapshot)
    VALUES(expense.id,actor,reviewer,p_kind,p_new_total,trim(p_reason),
      jsonb_build_object('expense',to_jsonb(expense),'shares',
        (SELECT jsonb_agg(to_jsonb(s) ORDER BY s.id) FROM public.transaction_participants s WHERE transaction_id=expense.id))) RETURNING id INTO result;
  INSERT INTO public.notifications(recipient_user_id,notification_type,related_tab_id,related_transaction_id,title,body)
    VALUES(reviewer,'amount_proposed',expense.tab_id,expense.id,'Expense change requested','Review a proposed change in your shared tab.');
  INSERT INTO public.financial_operations(actor_id,operation_id,command_kind,command,result_id)
    VALUES(actor,p_operation_id,'expense_change',command,result);
  RETURN result;
END $$;

CREATE FUNCTION public.decide_expense_change_v1(p_change_id uuid,p_accept boolean,p_expected_actor uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor uuid:=auth.uid(); change public.expense_change_requests;
  old_decision public.expense_change_decisions; expense public.transactions;
  payer public.transaction_participants; debtor public.transaction_participants;
  reversed uuid; replacement uuid; new_share bigint;
BEGIN
  SELECT * INTO change FROM public.expense_change_requests WHERE id=p_change_id;
  IF actor IS NULL OR actor IS DISTINCT FROM p_expected_actor OR change.id IS NULL OR actor IS DISTINCT FROM change.reviewer_id
    OR NOT public.is_tab_member((SELECT tab_id FROM public.transactions WHERE id=change.transaction_id),actor) THEN
    RAISE EXCEPTION 'Other expense participant must review' USING ERRCODE='42501';
  END IF;
  IF p_accept IS NULL THEN RAISE EXCEPTION 'Decision required' USING ERRCODE='22023'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(change.transaction_id::text,1));
  SELECT * INTO old_decision FROM public.expense_change_decisions WHERE change_id=change.id;
  IF FOUND THEN
    IF old_decision.accepted IS DISTINCT FROM p_accept THEN
      RAISE EXCEPTION 'Decision already recorded' USING ERRCODE='22023';
    END IF;
    RETURN change.id;
  END IF;
  IF EXISTS(SELECT 1 FROM public.expense_change_results WHERE transaction_id=change.transaction_id) THEN
    RAISE EXCEPTION 'Another revision was applied' USING ERRCODE='22023';
  END IF;
  SELECT * INTO expense FROM public.transactions WHERE id=change.transaction_id FOR SHARE;
  PERFORM 1 FROM public.transaction_participants WHERE transaction_id=expense.id FOR SHARE;
  IF change.original_snapshot IS DISTINCT FROM jsonb_build_object('expense',to_jsonb(expense),'shares',
    (SELECT jsonb_agg(to_jsonb(s) ORDER BY s.id) FROM public.transaction_participants s WHERE transaction_id=expense.id)) THEN
    RAISE EXCEPTION 'Original expense changed; request a fresh review' USING ERRCODE='22023';
  END IF;
  INSERT INTO public.expense_change_decisions(change_id,actor_id,accepted) VALUES(change.id,actor,p_accept);
  IF NOT p_accept THEN RETURN change.id; END IF;
  -- Use the same tab lock as settlement/receipt commands while appending money.
  PERFORM pg_advisory_xact_lock(hashtextextended(expense.tab_id::text,0));
  SELECT * INTO STRICT payer FROM public.transaction_participants WHERE transaction_id=expense.id AND participant_role='payer';
  SELECT * INTO STRICT debtor FROM public.transaction_participants WHERE transaction_id=expense.id AND id<>payer.id;
  IF debtor.share_amount_centavos>0 THEN
    reversed:=public.create_expense_atomic(expense.tab_id,
      'Reversal: '||expense.description,expense.category,debtor.share_amount_centavos,debtor.user_id,
      jsonb_build_array(
        jsonb_build_object('user_id',debtor.user_id,'participant_role','payer','share_amount_centavos',0),
        jsonb_build_object('user_id',payer.user_id,'participant_role','debtor','share_amount_centavos',debtor.share_amount_centavos)),
      NULL,NULL);
  END IF;
  IF change.kind='correct' THEN
    new_share:=trunc(change.new_total_centavos::numeric*debtor.share_amount_centavos/expense.total_amount_centavos)::bigint;
    replacement:=public.create_expense_atomic(expense.tab_id,
      expense.description,expense.category,change.new_total_centavos,payer.user_id,
      jsonb_build_array(
        jsonb_build_object('user_id',payer.user_id,'participant_role','payer','share_amount_centavos',change.new_total_centavos-new_share),
        jsonb_build_object('user_id',debtor.user_id,'participant_role',debtor.participant_role,'share_amount_centavos',new_share)),
      expense.due_date,expense.receipt_url);
  END IF;
  INSERT INTO public.expense_change_results(change_id,transaction_id,reversal_id,replacement_id)
    VALUES(change.id,expense.id,reversed,replacement);
  INSERT INTO public.activity_logs(actor_user_id,tab_id,transaction_id,event_type,metadata)
    VALUES(actor,expense.tab_id,expense.id,'EXPENSE_CHANGE_APPLIED',jsonb_build_object(
      'change_id',change.id,'kind',change.kind,'reason',change.reason,'reversal_id',reversed,'replacement_id',replacement));
  INSERT INTO public.notifications(recipient_user_id,notification_type,related_tab_id,related_transaction_id,title,body)
    VALUES(change.requested_by,'amount_changed',expense.tab_id,expense.id,'Expense change accepted','Your shared history now includes the agreed revision.');
  RETURN change.id;
END $$;

CREATE FUNCTION public.list_expense_changes_v1(p_transaction_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor uuid:=auth.uid(); result jsonb;
BEGIN
  IF actor IS NULL OR NOT EXISTS(SELECT 1 FROM public.transaction_participants s
    JOIN public.transactions t ON t.id=s.transaction_id WHERE s.transaction_id=p_transaction_id
      AND s.user_id=actor AND public.is_tab_member(t.tab_id,actor)) THEN
    RAISE EXCEPTION 'Expense participant required' USING ERRCODE='42501';
  END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id',r.id,'transaction_id',r.transaction_id,
    'requested_by',r.requested_by,'reviewer_id',r.reviewer_id,'kind',r.kind,
    'new_total_centavos',r.new_total_centavos,'reason',r.reason,'created_at',r.created_at,
    'status',CASE WHEN o.change_id IS NOT NULL THEN 'applied' WHEN d.accepted=false THEN 'rejected'
      WHEN EXISTS(SELECT 1 FROM public.expense_change_results x WHERE x.transaction_id=r.transaction_id) THEN 'superseded'
      ELSE 'pending' END,'reversal_id',o.reversal_id,'replacement_id',o.replacement_id)
    ORDER BY r.created_at,r.id),'[]'::jsonb) INTO result
  FROM public.expense_change_requests r LEFT JOIN public.expense_change_decisions d ON d.change_id=r.id
    LEFT JOIN public.expense_change_results o ON o.change_id=r.id WHERE r.transaction_id=p_transaction_id;
  RETURN jsonb_build_object('account_id',actor,'transaction_id',p_transaction_id,'changes',result,
    'can_request',NOT EXISTS(SELECT 1 FROM public.expense_change_results
      WHERE reversal_id=p_transaction_id OR transaction_id=p_transaction_id)
      AND EXISTS(SELECT 1 FROM public.transactions t JOIN public.tabs tab ON tab.id=t.tab_id
        WHERE t.id=p_transaction_id AND tab.tab_type='individual' AND t.status IN ('pending','acknowledged')
          AND t.total_amount_centavos BETWEEN 1 AND 99999999999
          AND tab.user_a IS NOT NULL AND tab.user_b IS NOT NULL
          AND (SELECT count(*) FROM public.transaction_participants s WHERE s.transaction_id=t.id AND s.user_id IN (tab.user_a,tab.user_b))=2)
      AND (SELECT count(*) FROM public.transaction_participants WHERE transaction_id=p_transaction_id)=2
      AND NOT EXISTS(SELECT 1 FROM public.transaction_participants WHERE transaction_id=p_transaction_id AND (contact_id IS NOT NULL OR user_id IS NULL))
      AND (SELECT count(*) FROM public.transaction_participants WHERE transaction_id=p_transaction_id AND participant_role='payer')=1);
END $$;
REVOKE ALL ON FUNCTION public.request_expense_change_v1(uuid,uuid,text,bigint,text,uuid),
  public.decide_expense_change_v1(uuid,boolean,uuid),public.list_expense_changes_v1(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.request_expense_change_v1(uuid,uuid,text,bigint,text,uuid),
  public.decide_expense_change_v1(uuid,boolean,uuid),public.list_expense_changes_v1(uuid) TO authenticated;
COMMIT;
