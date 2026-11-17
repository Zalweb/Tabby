-- HOME-004: exactly one accepted reminder per actor/operation. No client insert
-- fallback: an ambiguous network response is retried with the same operation ID.
CREATE TABLE public.reminder_operations (
  actor_id uuid NOT NULL REFERENCES public.users(id),
  operation_id uuid NOT NULL,
  command jsonb NOT NULL,
  notification_id uuid NOT NULL REFERENCES public.notifications(id),
  accepted_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(actor_id, operation_id)
);
ALTER TABLE public.reminder_operations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.reminder_operations FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.send_tab_reminder_v1(p_operation_id uuid, p_command jsonb)
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
  IF public.get_pair_outstanding(v_tab_id,recipient,actor)<=0 THEN
    RAISE EXCEPTION 'Recipient has no outstanding obligation to sender' USING ERRCODE='22023';
  END IF;
  IF coalesce(length(btrim(p_command->>'title')),0) NOT BETWEEN 1 AND 120 OR
     coalesce(length(btrim(p_command->>'body')),0) NOT BETWEEN 1 AND 1000 THEN
    RAISE EXCEPTION 'Reminder title/body invalid' USING ERRCODE='22023';
  END IF;
  IF EXISTS (SELECT 1 FROM public.reminder_operations r WHERE r.actor_id=actor
      AND r.command->>'tab_id'=v_tab_id::text AND r.command->>'recipient_user_id'=recipient::text
      AND r.accepted_at>now()-interval '1 minute') THEN
    RAISE EXCEPTION 'Please wait before sending another reminder' USING ERRCODE='22023';
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
DO $$ BEGIN
  IF to_regprocedure('public.send_tab_reminder(uuid,uuid,text,text)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.send_tab_reminder(uuid,uuid,text,text) FROM PUBLIC,anon,authenticated;
  END IF;
END $$;
DROP POLICY IF EXISTS "Tab members can queue reminders" ON public.notifications;
