BEGIN;

-- CAP-006 / ADR-006: cancellation is a status transition, never deletion or
-- amount mutation. The existing change result and reasoned activity remain the
-- durable revision record; the legacy status audit records the status change.
CREATE OR REPLACE FUNCTION public.prevent_transaction_tampering()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $function$
DECLARE v_uid text:=auth.uid()::text;
BEGIN
  IF NEW.tab_id IS DISTINCT FROM OLD.tab_id
     OR NEW.created_by IS DISTINCT FROM OLD.created_by
     OR NEW.recurring_rule_id IS DISTINCT FROM OLD.recurring_rule_id
     OR NEW.transaction_type IS DISTINCT FROM OLD.transaction_type
     OR NEW.category IS DISTINCT FROM OLD.category
     OR NEW.description IS DISTINCT FROM OLD.description
     OR NEW.total_amount_centavos IS DISTINCT FROM OLD.total_amount_centavos
     OR NEW.currency IS DISTINCT FROM OLD.currency
     OR NEW.transaction_date IS DISTINCT FROM OLD.transaction_date
     OR NEW.due_date IS DISTINCT FROM OLD.due_date
     OR (NEW.status IS DISTINCT FROM OLD.status AND NOT (
       NEW.status='cancelled' AND EXISTS(
         SELECT 1 FROM public.expense_change_results z
         JOIN public.expense_change_requests r ON r.id=z.change_id
         WHERE z.transaction_id=OLD.id AND r.kind='cancel'
       ))) THEN
    RAISE EXCEPTION 'Financial transaction fields cannot be changed';
  END IF;
  IF NEW.receipt_url IS DISTINCT FROM OLD.receipt_url AND NEW.receipt_url IS NOT NULL AND NEW.receipt_url<>'' THEN
    IF NEW.receipt_url ~* '^[a-z]+://' AND NEW.receipt_url !~* '^(file|content)://' THEN
      RAISE EXCEPTION 'Receipt attachments must be uploaded files';
    END IF;
    IF v_uid IS NOT NULL AND NEW.receipt_url NOT LIKE v_uid||'/%' AND left(NEW.receipt_url,1)<>'/'
       AND NEW.receipt_url !~* '^(file|content)://' AND NEW.receipt_url !~ '^[A-Za-z]:[\\/]' THEN
      RAISE EXCEPTION 'Receipt attachments must belong to the uploader';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.prevent_transaction_tampering() FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.apply_expense_change_internal(p_change_id uuid) RETURNS void
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
    IF change.kind='correct' AND party.share_amount_centavos>0 THEN
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
  IF change.kind='cancel' THEN
    -- Retain the original transaction and shares; update only lifecycle status.
    UPDATE public.transactions SET status='cancelled' WHERE id=expense.id AND status<>'cancelled';
  END IF;
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

-- HOME-002: preserve reminder rows as cancelled history after a pair settles.
-- Pair scoping prevents one group member's settlement from clearing others.
CREATE FUNCTION public.cancel_settled_pair_reminders_v1() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  IF NEW.status='confirmed' AND OLD.status IS DISTINCT FROM NEW.status
    AND COALESCE(NEW.payer_user_id,NEW.submitted_by) IS NOT NULL AND NEW.recipient_user_id IS NOT NULL THEN
    UPDATE public.reminders r SET status='cancelled'
      FROM public.transactions t
      WHERE r.transaction_id=t.id AND t.tab_id=NEW.tab_id AND r.status='scheduled'
        AND r.recipient_user_id=COALESCE(NEW.payer_user_id,NEW.submitted_by)
        AND r.created_by=NEW.recipient_user_id
        AND public.get_pair_outstanding(NEW.tab_id,COALESCE(NEW.payer_user_id,NEW.submitted_by),NEW.recipient_user_id)<=0;
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.cancel_settled_pair_reminders_v1() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER cancel_settled_pair_reminders
  AFTER UPDATE OF status ON public.payments
  FOR EACH ROW EXECUTE FUNCTION public.cancel_settled_pair_reminders_v1();

-- Repair legacy stale scheduled rows without deleting reminder history.
UPDATE public.reminders r SET status='cancelled'
  FROM public.transactions t
  WHERE r.transaction_id=t.id AND r.status='scheduled'
    AND public.get_pair_outstanding(t.tab_id,r.recipient_user_id,r.created_by)<=0;

-- HOME-004: idempotent replay is resolved before throttling. A new operation
-- inside the six-hour sender/tab/recipient window receives the stable PostgREST
-- contract HTTP 429 / SQLSTATE PT429 and commits no notification or operation.
CREATE OR REPLACE FUNCTION public.send_tab_reminder_v1(p_operation_id uuid, p_command jsonb)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  actor uuid := auth.uid();
  previous public.reminder_operations%ROWTYPE;
  v_tab_id uuid;
  recipient uuid;
  result uuid;
BEGIN
  IF actor IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='42501'; END IF;
  IF p_operation_id IS NULL OR p_command IS NULL OR jsonb_typeof(p_command)<>'object' THEN
    RAISE EXCEPTION 'Reminder command required' USING ERRCODE='22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':reminder',0));
  SELECT * INTO previous FROM public.reminder_operations
    WHERE actor_id=actor AND operation_id=p_operation_id;
  IF FOUND THEN
    IF previous.command<>p_command THEN RAISE EXCEPTION 'Operation payload conflict' USING ERRCODE='22023'; END IF;
    RETURN previous.notification_id;
  END IF;
  v_tab_id := (p_command->>'tab_id')::uuid;
  recipient := (p_command->>'recipient_user_id')::uuid;
  IF recipient IS NULL OR recipient=actor OR NOT EXISTS (
      SELECT 1 FROM public.tabs t JOIN public.tab_members a ON a.tab_id=t.id
      JOIN public.tab_members b ON b.tab_id=t.id WHERE t.id=v_tab_id
      AND t.status='active' AND a.user_id=actor AND b.user_id=recipient
      AND (t.group_id IS NULL OR (
        EXISTS(SELECT 1 FROM public.group_members g WHERE g.group_id=t.group_id AND g.user_id=actor AND g.status='active')
        AND EXISTS(SELECT 1 FROM public.group_members g WHERE g.group_id=t.group_id AND g.user_id=recipient AND g.status='active')))) THEN
    RAISE EXCEPTION 'Active shared tab required' USING ERRCODE='42501';
  END IF;
  -- Share the financial pair lock with payment confirmation so a reminder
  -- cannot pass its debt check concurrently with settlement.
  PERFORM pg_advisory_xact_lock(hashtextextended(v_tab_id::text,0));
  IF public.get_pair_outstanding(v_tab_id,recipient,actor)<=0 THEN
    RAISE EXCEPTION 'Recipient has no outstanding obligation to sender' USING ERRCODE='22023';
  END IF;
  IF coalesce(length(btrim(p_command->>'title')),0) NOT BETWEEN 1 AND 120 OR
     coalesce(length(btrim(p_command->>'body')),0) NOT BETWEEN 1 AND 1000 THEN
    RAISE EXCEPTION 'Reminder title/body invalid' USING ERRCODE='22023';
  END IF;
  IF EXISTS (SELECT 1 FROM public.reminder_operations r WHERE r.actor_id=actor
      AND r.command->>'tab_id'=v_tab_id::text AND r.command->>'recipient_user_id'=recipient::text
      AND r.accepted_at>now()-interval '6 hours') THEN
    RAISE SQLSTATE 'PT429'
      USING MESSAGE='Reminder rate limit exceeded',
        DETAIL='A reminder was already accepted for this tab and recipient within the last six hours',
        HINT='Retry after the six-hour pair window expires';
  END IF;
  INSERT INTO public.notifications(recipient_user_id,notification_type,related_tab_id,title,body)
    VALUES(recipient,'manual_nudge',v_tab_id,btrim(p_command->>'title'),btrim(p_command->>'body'))
    RETURNING id INTO result;
  INSERT INTO public.activity_logs(id,actor_user_id,tab_id,event_type,metadata)
    VALUES(result,actor,v_tab_id,'REMINDER_SENT',jsonb_build_object('recipient_id',recipient,'notification_id',result));
  INSERT INTO public.reminder_operations(actor_id,operation_id,command,notification_id)
    VALUES(actor,p_operation_id,p_command,result);
  RETURN result;
END; $$;
REVOKE ALL ON FUNCTION public.send_tab_reminder_v1(uuid,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.send_tab_reminder_v1(uuid,jsonb) TO authenticated;

COMMIT;
