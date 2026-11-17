BEGIN;
CREATE OR REPLACE FUNCTION public.require_m2_v1(p_feature text,p_operation uuid,p_command jsonb,p_kind text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor uuid:=auth.uid(); prior public.financial_operations;
BEGIN
  IF actor IS NOT NULL THEN PERFORM pg_advisory_xact_lock(hashtextextended('account-lifecycle:'||actor::text,0)); END IF;
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

CREATE TABLE public.recurrence_rules(
  id uuid PRIMARY KEY,owner_id uuid NOT NULL REFERENCES public.users(id),tab_id uuid NOT NULL REFERENCES public.tabs(id),
  anchor date NOT NULL,timezone text NOT NULL,unit text NOT NULL CHECK(unit IN ('daily','weekly','monthly')),
  step integer NOT NULL CHECK(step BETWEEN 1 AND 120),end_date date,template jsonb NOT NULL,
  status text NOT NULL DEFAULT 'active' CHECK(status IN ('active','paused','ended','needs_attention')),
  revision integer NOT NULL DEFAULT 1,effective_from date NOT NULL,next_index integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.recurrence_events(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),rule_id uuid NOT NULL REFERENCES public.recurrence_rules(id),
  revision integer NOT NULL,action text NOT NULL,snapshot jsonb NOT NULL,created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.recurrence_occurrences(rule_id uuid NOT NULL REFERENCES public.recurrence_rules(id),occurrence_date date NOT NULL,
  transaction_id uuid NOT NULL UNIQUE REFERENCES public.transactions(id),rule_revision integer NOT NULL,
  source text NOT NULL CHECK(source IN ('owner','scheduler')),created_at timestamptz NOT NULL DEFAULT now(),PRIMARY KEY(rule_id,occurrence_date));
ALTER TABLE public.recurrence_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recurrence_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recurrence_occurrences ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.recurrence_rules,public.recurrence_events,public.recurrence_occurrences FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.recurrence_date_v1(p_anchor date,p_unit text,p_step integer,p_index integer) RETURNS date
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog,public AS $$
BEGIN
  IF p_step IS NULL OR p_step NOT BETWEEN 1 AND 120 OR p_index IS NULL OR p_index NOT BETWEEN 0 AND 120000 OR p_anchor IS NULL THEN
    RAISE EXCEPTION 'Invalid recurrence calendar' USING ERRCODE='22023'; END IF;
  IF p_unit='monthly' THEN RETURN (p_anchor+make_interval(months=>p_step*p_index))::date;
  ELSIF p_unit='weekly' THEN RETURN p_anchor+(7*p_step*p_index);
  ELSIF p_unit='daily' THEN RETURN p_anchor+(p_step*p_index);
  ELSE RAISE EXCEPTION 'Invalid recurrence unit' USING ERRCODE='22023'; END IF;
END $$;
CREATE FUNCTION public.recurrence_index_v1(p_anchor date,p_unit text,p_step integer,p_day date) RETURNS integer
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog,public AS $$
DECLARE n integer;
BEGIN
  IF p_unit='monthly' THEN
    n:=greatest(0,((extract(year FROM p_day)::int-extract(year FROM p_anchor)::int)*12+
      extract(month FROM p_day)::int-extract(month FROM p_anchor)::int)/p_step);
  ELSE n:=greatest(0,(p_day-p_anchor)/(p_step*CASE WHEN p_unit='weekly' THEN 7 ELSE 1 END)); END IF;
  IF public.recurrence_date_v1(p_anchor,p_unit,p_step,n)<p_day THEN n:=n+1; END IF;
  RETURN n;
END $$;
REVOKE ALL ON FUNCTION public.recurrence_date_v1(date,text,integer,integer),public.recurrence_index_v1(date,text,integer,date) FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.change_recurrence_v1(p_operation_id uuid,p_command jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE result uuid; r public.recurrence_rules; action text:=p_command->>'action'; anchor date; zone text; unit text;
  step integer; ending date; template jsonb; allocated jsonb; today date;
BEGIN
  result:=public.require_m2_v1('recurring',p_operation_id,p_command,'m2_recurrence');IF result IS NOT NULL THEN RETURN result; END IF;
  IF p_command-ARRAY['p_expected_actor','action','rule_id','expected_revision','p_tab_id','anchor','timezone','unit','step','end_date','template']<>'{}'::jsonb THEN
    RAISE EXCEPTION 'Unsupported rule fields' USING ERRCODE='22023'; END IF;
  IF action IS NULL OR action NOT IN ('create','edit','pause','resume','end') THEN RAISE EXCEPTION 'Invalid rule action' USING ERRCODE='22023'; END IF;
  SELECT * INTO r FROM public.recurrence_rules WHERE id=(p_command->>'rule_id')::uuid FOR UPDATE;
  IF action='create' THEN
    IF r.id IS NOT NULL OR (p_command->>'expected_revision')::integer IS DISTINCT FROM 0 THEN RAISE EXCEPTION 'Rule already exists' USING ERRCODE='22023'; END IF;
    r.id:=(p_command->>'rule_id')::uuid;r.owner_id:=auth.uid();r.tab_id:=(p_command->>'p_tab_id')::uuid;
    r.anchor:=(p_command->>'anchor')::date;r.timezone:=p_command->>'timezone';r.revision:=1;r.status:='active';
  ELSE
    IF r.id IS NULL OR r.owner_id<>auth.uid() THEN RAISE EXCEPTION 'Rule not owned by caller' USING ERRCODE='42501'; END IF;
    IF r.revision IS DISTINCT FROM (p_command->>'expected_revision')::integer OR r.status='ended' THEN RAISE EXCEPTION 'Stale or ended rule' USING ERRCODE='22023'; END IF;
    IF (p_command ? 'anchor' AND (p_command->>'anchor')::date IS DISTINCT FROM r.anchor) OR
       (p_command ? 'timezone' AND p_command->>'timezone' IS DISTINCT FROM r.timezone) OR
       (p_command ? 'p_tab_id' AND (p_command->>'p_tab_id')::uuid IS DISTINCT FROM r.tab_id) THEN
      RAISE EXCEPTION 'Rule anchor, timezone and tab are immutable' USING ERRCODE='22023'; END IF;
    r.revision:=r.revision+1;
  END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=r.timezone) THEN RAISE EXCEPTION 'Unknown IANA timezone' USING ERRCODE='22023'; END IF;
  today:=(statement_timestamp() AT TIME ZONE r.timezone)::date;
  IF action IN ('create','edit') THEN
    r.unit:=p_command->>'unit';r.step:=(p_command->>'step')::integer;r.end_date:=(p_command->>'end_date')::date;
    r.template:=p_command->'template';
    IF (r.template ? 'p_expected_actor' AND (r.template->>'p_expected_actor')::uuid IS DISTINCT FROM r.owner_id) OR
      coalesce(r.template->>'p_receipt_url','')<>'' THEN RAISE EXCEPTION 'Rule cannot reuse receipts or another actor' USING ERRCODE='22023'; END IF;
    IF r.anchor IS NULL OR r.unit IS NULL OR r.unit NOT IN ('daily','weekly','monthly') OR r.step IS NULL OR r.step NOT BETWEEN 1 AND 120 OR
      (r.end_date IS NOT NULL AND r.end_date<r.anchor) OR r.template IS NULL OR
      (r.template->>'p_tab_id')::uuid IS DISTINCT FROM r.tab_id THEN RAISE EXCEPTION 'Invalid rule definition' USING ERRCODE='22023'; END IF;
    allocated:=public.allocate_custom_split_v1(r.template->'split',(r.template->>'p_paid_by_user_id')::uuid);
    IF (r.template->>'p_total_amount_centavos')::bigint IS DISTINCT FROM (allocated->>'total_centavos')::bigint OR
      r.template->'p_participants' IS DISTINCT FROM allocated->'participants' THEN RAISE EXCEPTION 'Rule allocation mismatch' USING ERRCODE='22023'; END IF;
    PERFORM public.validate_expense_roster_v2(r.tab_id,allocated->'participants',r.owner_id);
    r.effective_from:=greatest(r.anchor,today);r.next_index:=public.recurrence_index_v1(r.anchor,r.unit,r.step,r.effective_from);
  ELSIF action='pause' THEN r.status:='paused';
  ELSIF action='end' THEN r.status:='ended';
  ELSIF action='resume' THEN
    PERFORM public.validate_expense_roster_v2(r.tab_id,r.template->'p_participants',r.owner_id);
    r.status:='active';r.effective_from:=greatest(r.anchor,today);
    r.next_index:=public.recurrence_index_v1(r.anchor,r.unit,r.step,r.effective_from);
  END IF;
  IF action='create' THEN
    INSERT INTO public.recurrence_rules(id,owner_id,tab_id,anchor,timezone,unit,step,end_date,template,status,revision,effective_from,next_index)
      VALUES(r.id,r.owner_id,r.tab_id,r.anchor,r.timezone,r.unit,r.step,r.end_date,r.template,r.status,r.revision,r.effective_from,r.next_index);
  ELSE UPDATE public.recurrence_rules SET unit=r.unit,step=r.step,end_date=r.end_date,template=r.template,status=r.status,
    revision=r.revision,effective_from=r.effective_from,next_index=r.next_index WHERE id=r.id; END IF;
  INSERT INTO public.recurrence_events(rule_id,revision,action,snapshot) VALUES(r.id,r.revision,action,to_jsonb(r));
  RETURN public.record_m2_v1(p_operation_id,'m2_recurrence',p_command,r.id);
END $$;

-- The private writer is defined below. Only trusted routines can call it; it
-- validates the explicit rule owner and actual roster without setting JWT claims.
CREATE FUNCTION public.materialize_recurrence_internal_v1(p_rule uuid,p_date date,p_source text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE r public.recurrence_rules; result uuid; n integer; calculated jsonb; command jsonb;
BEGIN
  SELECT * INTO STRICT r FROM public.recurrence_rules WHERE id=p_rule FOR UPDATE;
  SELECT transaction_id INTO result FROM public.recurrence_occurrences WHERE rule_id=p_rule AND occurrence_date=p_date;
  IF result IS NOT NULL THEN
    IF p_date=public.recurrence_date_v1(r.anchor,r.unit,r.step,r.next_index) THEN
      UPDATE public.recurrence_rules SET next_index=r.next_index+1 WHERE id=r.id;
    END IF;
    RETURN result;
  END IF;
  n:=public.recurrence_index_v1(r.anchor,r.unit,r.step,p_date);
  IF p_date IS NULL OR r.status<>'active' OR p_date<r.effective_from OR
    (r.end_date IS NOT NULL AND p_date>r.end_date) OR public.recurrence_date_v1(r.anchor,r.unit,r.step,n)<>p_date OR
    (p_date::timestamp AT TIME ZONE r.timezone)>statement_timestamp() THEN
    RAISE EXCEPTION 'Occurrence not due or rule paused/ended' USING ERRCODE='22023'; END IF;
  calculated:=public.allocate_custom_split_v1(r.template->'split',(r.template->>'p_paid_by_user_id')::uuid);
  PERFORM public.validate_expense_roster_v2(r.tab_id,calculated->'participants',r.owner_id);
  result:=public.create_rule_expense_internal_v1(r.owner_id,r.tab_id,r.template->>'p_description',r.template->>'p_category',
    (calculated->>'total_centavos')::bigint,(r.template->>'p_paid_by_user_id')::uuid,calculated->'participants',p_date,NULL);
  INSERT INTO public.expense_split_details VALUES(result,(r.template->'split')||calculated,now());
  INSERT INTO public.recurrence_occurrences VALUES(r.id,p_date,result,r.revision,p_source,now());
  IF p_date=public.recurrence_date_v1(r.anchor,r.unit,r.step,r.next_index) THEN
    UPDATE public.recurrence_rules SET next_index=r.next_index+1 WHERE id=r.id;
  END IF;
  RETURN result;
END $$;
CREATE FUNCTION public.materialize_recurrence_v1(p_operation_id uuid,p_command jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE result uuid; r public.recurrence_rules;
BEGIN
  result:=public.require_m2_v1('recurring',p_operation_id,p_command,'m2_occurrence');IF result IS NOT NULL THEN RETURN result; END IF;
  SELECT * INTO r FROM public.recurrence_rules WHERE id=(p_command->>'rule_id')::uuid;
  IF r.id IS NULL OR r.owner_id<>auth.uid() THEN RAISE EXCEPTION 'Rule not owned' USING ERRCODE='42501'; END IF;
  result:=public.materialize_recurrence_internal_v1(r.id,(p_command->>'occurrence_date')::date,'owner');
  RETURN public.record_m2_v1(p_operation_id,'m2_occurrence',p_command,result);
END $$;
CREATE FUNCTION public.materialize_due_recurrences_v1(p_limit integer DEFAULT 25) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE r public.recurrence_rules; due_day date; count_created integer:=0; count_failed integer:=0;
BEGIN
  IF NOT coalesce((SELECT enabled FROM public.m2_feature_flags WHERE feature='recurring'),false) THEN RAISE EXCEPTION 'Feature awaiting acceptance' USING ERRCODE='42501'; END IF;
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'Invalid batch' USING ERRCODE='22023'; END IF;
  FOR r IN SELECT * FROM public.recurrence_rules WHERE status='active' AND
    (public.recurrence_date_v1(anchor,unit,step,next_index)::timestamp AT TIME ZONE timezone)<=statement_timestamp()
    ORDER BY (public.recurrence_date_v1(anchor,unit,step,next_index)::timestamp AT TIME ZONE timezone),id LIMIT p_limit FOR UPDATE SKIP LOCKED LOOP
    due_day:=public.recurrence_date_v1(r.anchor,r.unit,r.step,r.next_index);
    IF r.end_date IS NOT NULL AND due_day>r.end_date THEN UPDATE public.recurrence_rules SET status='ended' WHERE id=r.id;CONTINUE; END IF;
    BEGIN
      PERFORM public.materialize_recurrence_internal_v1(r.id,due_day,'scheduler');
      UPDATE public.recurrence_rules SET next_index=r.next_index+1 WHERE id=r.id;
      count_created:=count_created+1;
    EXCEPTION WHEN OTHERS THEN
      UPDATE public.recurrence_rules SET status='needs_attention' WHERE id=r.id;
      INSERT INTO public.recurrence_events(rule_id,revision,action,snapshot)
        VALUES(r.id,r.revision,'scheduler_failed',jsonb_build_object('code',SQLSTATE));
      count_failed:=count_failed+1;
    END;
  END LOOP;
  RETURN jsonb_build_object('processed',count_created,'needs_attention',count_failed);
END $$;
CREATE FUNCTION public.list_recurrences_v1(p_tab_id uuid,p_after uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE records jsonb; last_id uuid; more boolean;
BEGIN
  PERFORM public.tabby_pre_request();
  IF auth.uid() IS NULL OR NOT public.is_tab_member(p_tab_id,auth.uid()) THEN RAISE EXCEPTION 'Tab not authorized' USING ERRCODE='42501'; END IF;
  WITH window_rows AS (SELECT * FROM public.recurrence_rules WHERE owner_id=auth.uid() AND tab_id=p_tab_id
    AND (p_after IS NULL OR id>p_after) ORDER BY id LIMIT 51),page AS (SELECT * FROM window_rows ORDER BY id LIMIT 50)
  SELECT coalesce(jsonb_agg(to_jsonb(r)||jsonb_build_object('next_date',public.recurrence_date_v1(anchor,unit,step,next_index)) ORDER BY id),'[]'::jsonb),
    (SELECT id FROM page ORDER BY id DESC LIMIT 1),(SELECT count(*)>50 FROM window_rows) INTO records,last_id,more FROM page r;
  RETURN jsonb_build_object('account_id',auth.uid(),'tab_id',p_tab_id,'records',records,'next_cursor',CASE WHEN more THEN last_id ELSE NULL END);
END $$;
REVOKE ALL ON FUNCTION public.materialize_recurrence_internal_v1(uuid,date,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.change_recurrence_v1(uuid,jsonb),public.materialize_recurrence_v1(uuid,jsonb),public.list_recurrences_v1(uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.change_recurrence_v1(uuid,jsonb),public.materialize_recurrence_v1(uuid,jsonb),public.list_recurrences_v1(uuid,uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.materialize_due_recurrences_v1(integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.materialize_due_recurrences_v1(integer) TO service_role;
-- Private validated writer appended below.

CREATE FUNCTION public.create_rule_expense_internal_v1(
    p_actor UUID,
    p_tab_id UUID,
    p_description TEXT,
    p_category TEXT,
    p_total_amount_centavos BIGINT,
    p_paid_by_user_id UUID,
    p_participants JSONB,
    p_due_date DATE DEFAULT NULL,
    p_receipt_url TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_transaction_id UUID;
    v_participant JSONB;
    v_payer_count INTEGER := 0;
    v_share_total BIGINT := 0;
    v_user_id UUID;
    v_contact_id UUID;
    v_role TEXT;
    v_share BIGINT;
BEGIN
    PERFORM public.validate_expense_roster_v2(p_tab_id,p_participants,p_actor);
    IF p_actor IS NULL OR NOT public.is_tab_member(p_tab_id, p_actor) THEN
        RAISE EXCEPTION 'Not authorized to create an expense for this tab';
    END IF;
    IF p_total_amount_centavos IS NULL OR p_total_amount_centavos <= 0 THEN
        RAISE EXCEPTION 'Expense amount must be greater than zero';
    END IF;
    IF p_paid_by_user_id IS NULL
       OR (NOT public.is_tab_member(p_tab_id, p_paid_by_user_id) AND NOT EXISTS (
          SELECT 1 FROM public.contacts c JOIN public.tab_members tm ON tm.contact_id=c.id
          JOIN public.tabs t ON t.id=tm.tab_id
          WHERE c.id=p_paid_by_user_id AND c.owner_user_id=p_actor
            AND tm.tab_id=p_tab_id AND t.tab_type='individual')) THEN
        RAISE EXCEPTION 'Payer must be a member of the tab';
    END IF;
    IF jsonb_typeof(p_participants) <> 'array'
       OR jsonb_array_length(p_participants) = 0 THEN
        RAISE EXCEPTION 'At least one participant is required';
    END IF;

    FOR v_participant IN SELECT value FROM jsonb_array_elements(p_participants)
    LOOP
        v_user_id := NULLIF(v_participant->>'user_id', '')::UUID;
        v_contact_id := NULLIF(v_participant->>'contact_id', '')::UUID;
        v_role := COALESCE(v_participant->>'participant_role', 'debtor');
        v_share := COALESCE((v_participant->>'share_amount_centavos')::BIGINT, -1);

        IF (v_user_id IS NULL) = (v_contact_id IS NULL) THEN
            RAISE EXCEPTION 'Each participant must identify exactly one user or contact';
        END IF;
        IF v_share < 0 THEN
            RAISE EXCEPTION 'Participant share cannot be negative';
        END IF;
        IF v_role NOT IN ('payer', 'debtor', 'beneficiary') THEN
            RAISE EXCEPTION 'Invalid participant role';
        END IF;
        IF v_role = 'payer' THEN
            v_payer_count := v_payer_count + 1;
            IF COALESCE(v_user_id,v_contact_id) IS DISTINCT FROM p_paid_by_user_id THEN
                RAISE EXCEPTION 'Payer participant must match p_paid_by_user_id';
            END IF;
        END IF;
        IF v_user_id IS NOT NULL
           AND NOT public.is_tab_member(p_tab_id, v_user_id) THEN
            RAISE EXCEPTION 'User participant must be a member of the tab';
        END IF;
        IF v_contact_id IS NOT NULL
           AND NOT EXISTS (
               SELECT 1 FROM public.tab_members tm JOIN public.contacts c ON c.id=tm.contact_id
               JOIN public.tabs t ON t.id=tm.tab_id
               WHERE tm.tab_id=p_tab_id AND tm.contact_id=v_contact_id
                 AND c.owner_user_id=p_actor AND t.tab_type='individual'
           ) THEN
            RAISE EXCEPTION 'Contact participant must be a member of the tab';
        END IF;
        v_share_total := v_share_total + v_share;
    END LOOP;

    IF v_payer_count <> 1 THEN
        RAISE EXCEPTION 'Exactly one payer participant is required';
    END IF;
    IF v_share_total <> p_total_amount_centavos THEN
        RAISE EXCEPTION 'Participant shares must equal the total expense amount';
    END IF;

    INSERT INTO public.transactions (
        tab_id, created_by, transaction_type, category, description,
        total_amount_centavos, currency, status, due_date, receipt_url
    ) VALUES (
        p_tab_id, p_actor, 'shared_expense',
        COALESCE(NULLIF(trim(p_category), ''), 'other'),
        COALESCE(NULLIF(trim(p_description), ''), 'Expense'),
        p_total_amount_centavos, 'PHP', 'acknowledged',
        p_due_date, p_receipt_url
    )
    RETURNING id INTO v_transaction_id;

    INSERT INTO public.transaction_participants (
        transaction_id, user_id, contact_id, participant_role,
        share_amount_centavos, acknowledged
    )
    SELECT
        v_transaction_id,
        NULLIF(value->>'user_id', '')::UUID,
        NULLIF(value->>'contact_id', '')::UUID,
        COALESCE(value->>'participant_role', 'debtor'),
        (value->>'share_amount_centavos')::BIGINT,
        COALESCE((value->>'acknowledged')::BOOLEAN, false)
    FROM jsonb_array_elements(p_participants);

    RETURN v_transaction_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public;



REVOKE ALL ON FUNCTION public.create_rule_expense_internal_v1(uuid,uuid,text,text,bigint,uuid,jsonb,date,text) FROM PUBLIC,anon,authenticated;

-- Retire private scheduling state during the existing reviewed privacy flow.
ALTER FUNCTION public.prepare_account_deletion_v1(uuid) RENAME TO prepare_account_deletion_core_v1;
REVOKE ALL ON FUNCTION public.prepare_account_deletion_core_v1(uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.prepare_account_deletion_v1(p_request_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE result jsonb; actor uuid;
BEGIN
  SELECT user_id INTO STRICT actor FROM public.account_deletion_requests WHERE id=p_request_id;
  PERFORM pg_advisory_xact_lock(hashtextextended('account-lifecycle:'||actor::text,0));
  PERFORM id FROM public.recurrence_rules WHERE owner_id=actor ORDER BY id FOR UPDATE;
  result:=public.prepare_account_deletion_core_v1(p_request_id);
  UPDATE public.recurrence_events SET snapshot=jsonb_build_object('redacted',true,'revision',revision)
    WHERE rule_id IN (SELECT id FROM public.recurrence_rules WHERE owner_id=actor);
  UPDATE public.recurrence_rules SET status='ended',template='{}'::jsonb WHERE owner_id=actor;
  RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.prepare_account_deletion_v1(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_account_deletion_v1(uuid) TO service_role;
CREATE FUNCTION public.get_expense_split_v1(p_transaction_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE result jsonb;
BEGIN
  PERFORM public.tabby_pre_request();
  IF NOT public.can_read_expense_split_v1(p_transaction_id) THEN RAISE EXCEPTION 'Expense not authorized' USING ERRCODE='42501'; END IF;
  SELECT breakdown INTO result FROM public.expense_split_details WHERE transaction_id=p_transaction_id;
  RETURN jsonb_build_object('account_id',auth.uid(),'transaction_id',p_transaction_id,'breakdown',result);
END $$;
REVOKE ALL ON FUNCTION public.get_expense_split_v1(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_expense_split_v1(uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.protect_profile_identity_v1() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  IF TG_OP='UPDATE' AND OLD.anonymized_at IS NOT NULL AND current_setting('role',true) IN ('anon','authenticated') THEN
    RAISE EXCEPTION 'Account no longer active' USING ERRCODE='42501';
  END IF;
  IF TG_OP='UPDATE' AND OLD.anonymized_at IS NOT NULL THEN NEW.anonymized_at:=OLD.anonymized_at; END IF;
  IF NEW.anonymized_at IS NOT NULL AND current_setting('role',true) NOT IN ('anon','authenticated') THEN
    -- Auth's profile-upsert trigger must not restore PII during soft deletion.
    NEW.display_name:='Former member'; NEW.email:=NULL; NEW.phone:=NULL; NEW.avatar_url:=NULL;
    NEW.gcash_number:=NULL; NEW.maya_number:=NULL; NEW.qr_code_url:=NULL;
    RETURN NEW;
  END IF;
  IF NEW.email IS DISTINCT FROM (CASE WHEN TG_OP='UPDATE' THEN OLD.email ELSE NULL END)
     AND NEW.email IS DISTINCT FROM (SELECT email FROM auth.users WHERE id=NEW.id) THEN
    RAISE EXCEPTION 'Profile email must match Auth' USING ERRCODE='42501';
  END IF;
  IF current_setting('role',true) IN ('anon','authenticated') THEN
    IF TG_OP='INSERT' THEN
      IF coalesce(NEW.gcash_number,'')<>'' OR coalesce(NEW.maya_number,'')<>'' OR coalesce(NEW.qr_code_url,'')<>'' THEN
        RAISE EXCEPTION 'Use saved receiving methods' USING ERRCODE='42501'; END IF;
    ELSIF NEW.gcash_number IS DISTINCT FROM OLD.gcash_number OR NEW.maya_number IS DISTINCT FROM OLD.maya_number
      OR NEW.qr_code_url IS DISTINCT FROM OLD.qr_code_url THEN
      RAISE EXCEPTION 'Use saved receiving methods' USING ERRCODE='42501';
    END IF;
  END IF;
  RETURN NEW;
END $$;


COMMIT;
