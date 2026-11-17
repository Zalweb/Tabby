BEGIN;
-- Rollout rollback denies new intents, while exact recorded replays still recover.
CREATE OR REPLACE FUNCTION public.require_m2_v1(p_feature text,p_operation uuid,p_command jsonb,p_kind text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor uuid:=auth.uid(); prior public.financial_operations;
BEGIN
  IF actor IS NOT NULL THEN PERFORM pg_advisory_xact_lock(hashtextextended('account-lifecycle:'||actor::text,0)); END IF;
  PERFORM public.tabby_pre_request();
  IF actor IS NULL OR actor IS DISTINCT FROM (p_command->>'p_expected_actor')::uuid THEN
    RAISE EXCEPTION 'Account changed' USING ERRCODE='42501'; END IF;
  IF p_operation IS NULL OR p_command IS NULL OR jsonb_typeof(p_command)<>'object' THEN
    RAISE EXCEPTION 'Operation and command required' USING ERRCODE='22023'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':'||p_operation::text,0));
  SELECT * INTO prior FROM public.financial_operations WHERE actor_id=actor AND operation_id=p_operation;
  IF FOUND THEN
    IF prior.command_kind<>p_kind OR prior.command IS DISTINCT FROM p_command THEN
      RAISE EXCEPTION 'Operation payload conflict' USING ERRCODE='22023'; END IF;
    RETURN prior.result_id;
  END IF;
  IF NOT coalesce((SELECT enabled FROM public.m2_feature_flags WHERE feature=p_feature),false) THEN
    RAISE EXCEPTION 'Feature awaiting acceptance' USING ERRCODE='42501'; END IF;
  RETURN NULL;
END $$;

CREATE TABLE public.expense_acknowledgments(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),transaction_id uuid NOT NULL REFERENCES public.transactions(id),actor_id uuid NOT NULL REFERENCES public.users(id),created_at timestamptz NOT NULL DEFAULT now(),UNIQUE(transaction_id,actor_id));
CREATE TABLE public.expense_disputes(id uuid PRIMARY KEY,transaction_id uuid NOT NULL REFERENCES public.transactions(id),opened_by uuid NOT NULL REFERENCES public.users(id),reason text NOT NULL CHECK(length(trim(reason)) BETWEEN 1 AND 500),required_parties uuid[] NOT NULL,status text NOT NULL DEFAULT 'open' CHECK(status IN ('open','resolved')),resolution_id uuid,resolved_at timestamptz,created_at timestamptz NOT NULL DEFAULT now());
CREATE UNIQUE INDEX ON public.expense_disputes(transaction_id) WHERE status='open';
CREATE TABLE public.expense_dispute_resolutions(id uuid PRIMARY KEY,dispute_id uuid NOT NULL REFERENCES public.expense_disputes(id),proposed_by uuid NOT NULL REFERENCES public.users(id),resolution text NOT NULL CHECK(length(trim(resolution)) BETWEEN 1 AND 500),status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','rejected','agreed')),created_at timestamptz NOT NULL DEFAULT now());
CREATE UNIQUE INDEX ON public.expense_dispute_resolutions(dispute_id) WHERE status='pending';
CREATE TABLE public.expense_resolution_votes(resolution_id uuid NOT NULL REFERENCES public.expense_dispute_resolutions(id),actor_id uuid NOT NULL REFERENCES public.users(id),accepted boolean NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),PRIMARY KEY(resolution_id,actor_id));
ALTER TABLE public.expense_acknowledgments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expense_disputes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expense_dispute_resolutions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expense_resolution_votes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.expense_acknowledgments,public.expense_disputes,public.expense_dispute_resolutions,public.expense_resolution_votes FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.review_expense_v1(p_operation_id uuid,p_command jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE result uuid;expense public.transactions;d public.expense_disputes;r public.expense_dispute_resolutions;
 actor uuid:=auth.uid();action text:=p_command->>'action';parties uuid[];previous boolean;context jsonb;
BEGIN
 result:=public.require_m2_v1('expense_review',p_operation_id,p_command,'m2_review');IF result IS NOT NULL THEN RETURN result;END IF;
 IF action IS NULL OR action NOT IN ('acknowledge','propose','decide_proposal','open_dispute','propose_resolution','vote_resolution') THEN RAISE EXCEPTION 'Invalid review action' USING ERRCODE='22023';END IF;
 IF p_command-ARRAY['p_expected_actor','transaction_id','action','kind','new_total_centavos','reason','change_id','accept','dispute_id','resolution_id','resolution']<>'{}' THEN RAISE EXCEPTION 'Unsupported review fields' USING ERRCODE='22023';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended((p_command->>'transaction_id'),1));
 SELECT * INTO expense FROM public.transactions WHERE id=(p_command->>'transaction_id')::uuid;
 context:=public.expense_change_context_internal(expense.id,actor);
 IF expense.id IS NULL OR context IS NULL OR coalesce((context->>'manual_contact')::boolean,true) OR
 EXISTS(SELECT 1 FROM public.transaction_participants s JOIN public.users u ON u.id=s.user_id WHERE s.transaction_id=expense.id AND u.anonymized_at IS NOT NULL) THEN RAISE EXCEPTION 'Active registered expense parties required' USING ERRCODE='42501';END IF;
 SELECT array_agg(DISTINCT user_id ORDER BY user_id) INTO parties FROM public.transaction_participants WHERE transaction_id=expense.id;
 IF action='acknowledge' THEN
  IF actor=expense.created_by THEN RAISE EXCEPTION 'Creator cannot self-acknowledge' USING ERRCODE='42501';END IF;
  INSERT INTO public.expense_acknowledgments(transaction_id,actor_id) VALUES(expense.id,actor) ON CONFLICT DO NOTHING;
  SELECT id INTO result FROM public.expense_acknowledgments WHERE transaction_id=expense.id AND actor_id=actor;
 ELSIF action='propose' THEN
  -- A distinct deterministic inner operation preserves CAP-006's public replay
  -- contract. The outer operation records the exact M2 intent in the same registry.
  result:=public.request_expense_change_v2(md5('m2-proposal:'||actor::text||':'||p_operation_id::text)::uuid,expense.id,p_command->>'kind',(p_command->>'new_total_centavos')::bigint,p_command->>'reason',actor,false);
 ELSIF action='decide_proposal' THEN
  IF jsonb_typeof(p_command->'accept') IS DISTINCT FROM 'boolean' OR NOT EXISTS(SELECT 1 FROM public.expense_change_requests WHERE id=(p_command->>'change_id')::uuid AND transaction_id=expense.id) THEN RAISE EXCEPTION 'Proposal/decision mismatch' USING ERRCODE='22023';END IF;
  result:=public.decide_expense_change_v1((p_command->>'change_id')::uuid,(p_command->>'accept')::boolean,actor);
 ELSIF action='open_dispute' THEN
  IF cardinality(parties)<2 OR length(trim(coalesce(p_command->>'reason',''))) NOT BETWEEN 1 AND 500 THEN RAISE EXCEPTION 'Reason and affected parties required' USING ERRCODE='22023';END IF;
  INSERT INTO public.expense_disputes(id,transaction_id,opened_by,reason,required_parties) VALUES((p_command->>'dispute_id')::uuid,expense.id,actor,p_command->>'reason',parties) RETURNING id INTO result;
 ELSE
  SELECT * INTO d FROM public.expense_disputes WHERE id=(p_command->>'dispute_id')::uuid AND transaction_id=expense.id FOR UPDATE;
  IF d.id IS NULL OR NOT actor=ANY(d.required_parties) THEN RAISE EXCEPTION 'Dispute party required' USING ERRCODE='42501';END IF;
  IF action='propose_resolution' THEN
   IF d.status<>'open' OR length(trim(coalesce(p_command->>'resolution',''))) NOT BETWEEN 1 AND 500 THEN RAISE EXCEPTION 'Open dispute and resolution required' USING ERRCODE='22023';END IF;
   INSERT INTO public.expense_dispute_resolutions(id,dispute_id,proposed_by,resolution) VALUES((p_command->>'resolution_id')::uuid,d.id,actor,p_command->>'resolution') RETURNING id INTO result;
   INSERT INTO public.expense_resolution_votes VALUES(result,actor,true,now());
  ELSE
   SELECT * INTO r FROM public.expense_dispute_resolutions WHERE id=(p_command->>'resolution_id')::uuid AND dispute_id=d.id FOR UPDATE;
   IF r.id IS NULL OR jsonb_typeof(p_command->'accept') IS DISTINCT FROM 'boolean' THEN RAISE EXCEPTION 'Resolution and explicit vote required' USING ERRCODE='22023';END IF;
   SELECT accepted INTO previous FROM public.expense_resolution_votes WHERE resolution_id=r.id AND actor_id=actor;
   IF FOUND THEN
    IF previous IS DISTINCT FROM (p_command->>'accept')::boolean THEN RAISE EXCEPTION 'Vote conflict' USING ERRCODE='22023';END IF;
   ELSE
    IF d.status<>'open' OR r.status<>'pending' THEN RAISE EXCEPTION 'Resolution already decided' USING ERRCODE='22023';END IF;
    INSERT INTO public.expense_resolution_votes VALUES(r.id,actor,(p_command->>'accept')::boolean,now());
    IF NOT (p_command->>'accept')::boolean THEN UPDATE public.expense_dispute_resolutions SET status='rejected' WHERE id=r.id;
    ELSIF NOT EXISTS(SELECT 1 FROM unnest(d.required_parties) AS p(id) WHERE NOT EXISTS(SELECT 1 FROM public.expense_resolution_votes WHERE resolution_id=r.id AND actor_id=p.id AND accepted)) THEN
     UPDATE public.expense_dispute_resolutions SET status='agreed' WHERE id=r.id;
     UPDATE public.expense_disputes SET status='resolved',resolution_id=r.id,resolved_at=now() WHERE id=d.id;
    END IF;
   END IF;result:=r.id;
  END IF;
 END IF;
 RETURN public.record_m2_v1(p_operation_id,'m2_review',p_command,result);
END $$;
CREATE FUNCTION public.expense_review_state_v1(p_transaction_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor uuid:=auth.uid();expense public.transactions;ack jsonb;disputes jsonb;changes jsonb;context jsonb;
BEGIN
 PERFORM public.tabby_pre_request();SELECT * INTO expense FROM public.transactions WHERE id=p_transaction_id;
 IF actor IS NULL OR expense.id IS NULL OR NOT public.is_tab_member(expense.tab_id,actor) OR NOT EXISTS(SELECT 1 FROM public.transaction_participants WHERE transaction_id=expense.id AND user_id=actor) THEN RAISE EXCEPTION 'Expense party required' USING ERRCODE='42501';END IF;
 context:=public.expense_change_context_internal(expense.id,actor);
 SELECT coalesce(jsonb_agg(jsonb_build_object('actor_id',s.user_id,'required',s.user_id<>expense.created_by,'acknowledged',a.id IS NOT NULL,'acknowledged_at',a.created_at) ORDER BY s.user_id),'[]') INTO ack FROM public.transaction_participants s LEFT JOIN public.expense_acknowledgments a ON a.transaction_id=s.transaction_id AND a.actor_id=s.user_id WHERE s.transaction_id=expense.id AND s.user_id IS NOT NULL;
 SELECT coalesce(jsonb_agg(value ORDER BY created_at DESC,id),'[]') INTO changes FROM(
 SELECT r.created_at,r.id,jsonb_build_object('id',r.id,'requested_by',r.requested_by,'kind',r.kind,'new_total_centavos',r.new_total_centavos,'reason',r.reason,
 'can_review',o.change_id IS NULL AND NOT EXISTS(SELECT 1 FROM public.expense_change_results WHERE transaction_id=r.transaction_id) AND NOT EXISTS(SELECT 1 FROM public.expense_change_decisions WHERE change_id=r.id AND NOT accepted) AND EXISTS(SELECT 1 FROM public.expense_change_reviewers WHERE change_id=r.id AND reviewer_id=actor) AND NOT EXISTS(SELECT 1 FROM public.expense_change_decisions WHERE change_id=r.id AND actor_id=actor),
 'status',CASE WHEN o.change_id IS NOT NULL THEN 'applied' WHEN EXISTS(SELECT 1 FROM public.expense_change_decisions WHERE change_id=r.id AND NOT accepted) THEN 'rejected' WHEN EXISTS(SELECT 1 FROM public.expense_change_results WHERE transaction_id=r.transaction_id) THEN 'superseded' ELSE 'pending' END,
 'required_reviewers',(SELECT count(*) FROM public.expense_change_reviewers WHERE change_id=r.id),'accepted_reviewers',(SELECT count(*) FROM public.expense_change_reviewers v JOIN public.expense_change_decisions d ON d.change_id=v.change_id AND d.actor_id=v.reviewer_id WHERE v.change_id=r.id AND d.accepted)) value
 FROM public.expense_change_requests r LEFT JOIN public.expense_change_results o ON o.change_id=r.id WHERE r.transaction_id=expense.id ORDER BY r.created_at DESC,r.id LIMIT 50) rows;
 SELECT coalesce(jsonb_agg(value ORDER BY status,created_at DESC,id),'[]') INTO disputes FROM(
 SELECT d.id,d.status,d.created_at,to_jsonb(d)||jsonb_build_object('resolutions',coalesce((SELECT jsonb_agg(to_jsonb(r)||jsonb_build_object('accepted_count',(SELECT count(*) FROM public.expense_resolution_votes WHERE resolution_id=r.id AND accepted),'my_vote',(SELECT accepted FROM public.expense_resolution_votes WHERE resolution_id=r.id AND actor_id=actor)) ORDER BY r.created_at DESC,r.id) FROM (SELECT * FROM public.expense_dispute_resolutions WHERE dispute_id=d.id ORDER BY (status='pending') DESC,created_at DESC,id LIMIT 50) r),'[]')) value
 FROM public.expense_disputes d WHERE transaction_id=expense.id ORDER BY (status='open') DESC,created_at DESC,id LIMIT 50) rows;
 RETURN jsonb_build_object('account_id',actor,'transaction_id',expense.id,'expense',jsonb_build_object('description',expense.description,'total_centavos',expense.total_amount_centavos,'created_by',expense.created_by),'acknowledgments',ack,'proposals',changes,'disputes',disputes,
 'can_acknowledge',context IS NOT NULL AND NOT coalesce((context->>'manual_contact')::boolean,true) AND actor<>expense.created_by AND NOT EXISTS(SELECT 1 FROM public.expense_acknowledgments WHERE transaction_id=expense.id AND actor_id=actor),
 'can_propose',context IS NOT NULL AND coalesce((context->>'can_request')::boolean,false) AND NOT coalesce((context->>'manual_contact')::boolean,true),
 'can_dispute',context IS NOT NULL AND NOT coalesce((context->>'manual_contact')::boolean,true) AND NOT EXISTS(SELECT 1 FROM public.expense_disputes WHERE transaction_id=expense.id AND status='open'));
END $$;
REVOKE ALL ON FUNCTION public.review_expense_v1(uuid,jsonb),public.expense_review_state_v1(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.review_expense_v1(uuid,jsonb),public.expense_review_state_v1(uuid) TO authenticated;
CREATE FUNCTION public.expense_review_history_v1(p_transaction_id uuid,p_section text,p_parent_id uuid DEFAULT NULL,p_after uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor uuid:=auth.uid();records jsonb;last_id uuid;more boolean;expense public.transactions;
BEGIN
 PERFORM public.tabby_pre_request();SELECT * INTO expense FROM public.transactions WHERE id=p_transaction_id;
 IF actor IS NULL OR expense.id IS NULL OR NOT public.is_tab_member(expense.tab_id,actor) OR NOT EXISTS(SELECT 1 FROM public.transaction_participants WHERE transaction_id=expense.id AND user_id=actor) THEN RAISE EXCEPTION 'Expense party required' USING ERRCODE='42501';END IF;
 IF p_section IS NULL OR p_section NOT IN ('proposals','disputes','resolutions') OR (p_section='resolutions' AND NOT EXISTS(SELECT 1 FROM public.expense_disputes WHERE id=p_parent_id AND transaction_id=expense.id)) OR (p_section<>'resolutions' AND p_parent_id IS NOT NULL) THEN RAISE EXCEPTION 'History scope mismatch' USING ERRCODE='22023';END IF;
 WITH candidates AS (
 SELECT r.id,to_jsonb(r)||jsonb_build_object(
 'status',CASE WHEN o.change_id IS NOT NULL THEN 'applied' WHEN EXISTS(SELECT 1 FROM public.expense_change_decisions WHERE change_id=r.id AND NOT accepted) THEN 'rejected' WHEN EXISTS(SELECT 1 FROM public.expense_change_results WHERE transaction_id=r.transaction_id) THEN 'superseded' ELSE 'pending' END,
 'can_review',o.change_id IS NULL AND NOT EXISTS(SELECT 1 FROM public.expense_change_results WHERE transaction_id=r.transaction_id) AND NOT EXISTS(SELECT 1 FROM public.expense_change_decisions WHERE change_id=r.id AND NOT accepted) AND EXISTS(SELECT 1 FROM public.expense_change_reviewers WHERE change_id=r.id AND reviewer_id=actor) AND NOT EXISTS(SELECT 1 FROM public.expense_change_decisions WHERE change_id=r.id AND actor_id=actor)) value
 FROM public.expense_change_requests r LEFT JOIN public.expense_change_results o ON o.change_id=r.id WHERE p_section='proposals' AND r.transaction_id=expense.id
 UNION ALL SELECT d.id,to_jsonb(d)||jsonb_build_object('has_pending_resolution',EXISTS(SELECT 1 FROM public.expense_dispute_resolutions WHERE dispute_id=d.id AND status='pending')) FROM public.expense_disputes d WHERE p_section='disputes' AND transaction_id=expense.id
 UNION ALL SELECT r.id,to_jsonb(r)||jsonb_build_object('required_party_count',cardinality(d.required_parties),'accepted_count',(SELECT count(*) FROM public.expense_resolution_votes WHERE resolution_id=r.id AND accepted),'can_vote',d.status='open' AND r.status='pending' AND actor=ANY(d.required_parties) AND NOT EXISTS(SELECT 1 FROM public.expense_resolution_votes WHERE resolution_id=r.id AND actor_id=actor))
 FROM public.expense_dispute_resolutions r JOIN public.expense_disputes d ON d.id=r.dispute_id WHERE p_section='resolutions' AND d.id=p_parent_id AND d.transaction_id=expense.id
 ),window_rows AS(SELECT * FROM candidates WHERE p_after IS NULL OR id>p_after ORDER BY id LIMIT 51),page AS(SELECT * FROM window_rows ORDER BY id LIMIT 50)
 SELECT coalesce(jsonb_agg(value ORDER BY id),'[]'),(SELECT id FROM page ORDER BY id DESC LIMIT 1),(SELECT count(*)>50 FROM window_rows) INTO records,last_id,more FROM page;
 RETURN jsonb_build_object('account_id',actor,'transaction_id',expense.id,'section',p_section,'parent_id',p_parent_id,'records',records,'next_cursor',CASE WHEN more THEN last_id ELSE NULL END,
 'expense',jsonb_build_object('description',expense.description,'total_centavos',expense.total_amount_centavos));
END $$;
REVOKE ALL ON FUNCTION public.expense_review_history_v1(uuid,text,uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.expense_review_history_v1(uuid,text,uuid,uuid) TO authenticated;

COMMIT;