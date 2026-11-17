-- HOME-004: private account-bound endpoints and leased background delivery jobs.
-- Tokens never appear in user-readable tables, activity metadata or app logs.
CREATE TABLE public.push_device_bindings (
  installation_id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  binding_id uuid NOT NULL,
  token text NOT NULL CHECK(length(token) BETWEEN 20 AND 4096),
  reminders_enabled boolean NOT NULL DEFAULT false,
  expires_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX push_device_token_unique ON public.push_device_bindings(token);
CREATE TABLE public.push_delivery_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  notification_id uuid NOT NULL REFERENCES public.notifications(id) ON DELETE CASCADE,
  installation_id uuid NOT NULL,
  binding_id uuid NOT NULL,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','sending','accepted','cancelled','failed')),
  token_hash text NOT NULL,
  attempts integer NOT NULL DEFAULT 0,
  next_attempt_at timestamptz NOT NULL DEFAULT now(),
  lease_id uuid,
  lease_until timestamptz,
  error_code text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(notification_id,installation_id,binding_id)
);
CREATE INDEX push_jobs_ready ON public.push_delivery_jobs(next_attempt_at) WHERE status IN ('pending','sending');
ALTER TABLE public.push_device_bindings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.push_delivery_jobs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.push_device_bindings,public.push_delivery_jobs FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.register_push_device_v1(p_installation_id uuid,p_binding_id uuid,p_token text,p_reminders_enabled boolean)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE actor uuid:=auth.uid();
BEGIN
  IF actor IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='42501'; END IF;
  IF p_installation_id IS NULL OR p_binding_id IS NULL OR p_reminders_enabled IS NULL
    OR coalesce(length(p_token),0) NOT BETWEEN 20 AND 4096 THEN
    RAISE EXCEPTION 'Invalid push registration' USING ERRCODE='22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('push:'||p_installation_id::text,0));
  -- A Firebase token can rotate/reappear under a restored installation. Only one
  -- active association is retained; neither endpoint nor token is client-readable.
  DELETE FROM public.push_device_bindings WHERE token=p_token AND installation_id<>p_installation_id;
  INSERT INTO public.push_device_bindings(installation_id,user_id,binding_id,token,reminders_enabled,expires_at)
    VALUES(p_installation_id,actor,p_binding_id,p_token,p_reminders_enabled,now()+interval '1 day')
    ON CONFLICT(installation_id) DO UPDATE SET user_id=EXCLUDED.user_id,binding_id=EXCLUDED.binding_id,
      token=EXCLUDED.token,reminders_enabled=EXCLUDED.reminders_enabled,expires_at=EXCLUDED.expires_at,updated_at=now();
  UPDATE public.push_delivery_jobs SET status='cancelled',lease_id=NULL,lease_until=NULL
    WHERE installation_id=p_installation_id AND status IN ('pending','sending')
    AND (binding_id<>p_binding_id OR user_id<>actor OR NOT p_reminders_enabled
      OR token_hash<>encode(sha256(convert_to(p_token,'UTF8')),'hex'));
  RETURN true;
END; $$;

CREATE FUNCTION public.revoke_push_device_v1(p_installation_id uuid,p_binding_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='42501'; END IF;
  DELETE FROM public.push_device_bindings WHERE installation_id=p_installation_id AND binding_id=p_binding_id AND user_id=auth.uid();
  IF NOT FOUND THEN RETURN false; END IF;
  UPDATE public.push_delivery_jobs SET status='cancelled',lease_id=NULL,lease_until=NULL
    WHERE installation_id=p_installation_id AND binding_id=p_binding_id AND status IN ('pending','sending');
  RETURN true;
END; $$;

CREATE FUNCTION public.enqueue_reminder_push_v1() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  IF NEW.notification_type IN ('manual_nudge','tab_reminder') THEN
    INSERT INTO public.push_delivery_jobs(notification_id,installation_id,binding_id,user_id,token_hash)
      SELECT NEW.id,d.installation_id,d.binding_id,d.user_id,encode(sha256(convert_to(d.token,'UTF8')),'hex') FROM public.push_device_bindings d
      WHERE d.user_id=NEW.recipient_user_id AND d.reminders_enabled AND d.expires_at>now()
      ON CONFLICT DO NOTHING;
  END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER enqueue_reminder_push AFTER INSERT ON public.notifications
  FOR EACH ROW EXECUTE FUNCTION public.enqueue_reminder_push_v1();

CREATE FUNCTION public.claim_reminder_push_v1(p_limit integer DEFAULT 50)
RETURNS TABLE(job_id uuid,lease_id uuid,notification_id uuid,user_id uuid,binding_id uuid,tab_id uuid,token text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  -- Remove stale associations before acquiring jobs. Native receivers also check
  -- the exact binding, covering messages already in flight during logout.
  UPDATE public.push_delivery_jobs j SET status='cancelled',lease_id=NULL,lease_until=NULL
    WHERE j.status IN ('pending','sending') AND NOT EXISTS (
      SELECT 1 FROM public.push_device_bindings d JOIN public.notifications n ON n.id=j.notification_id
      JOIN public.tabs t ON t.id=n.related_tab_id
      JOIN public.tab_members m ON m.tab_id=t.id AND m.user_id=d.user_id
      WHERE d.installation_id=j.installation_id AND d.binding_id=j.binding_id AND d.user_id=j.user_id
      AND j.token_hash=encode(sha256(convert_to(d.token,'UTF8')),'hex')
      AND d.user_id=n.recipient_user_id AND d.reminders_enabled AND d.expires_at>now() AND t.status='active'
      AND EXISTS(SELECT 1 FROM public.reminder_operations r WHERE r.notification_id=n.id
        AND public.get_pair_outstanding(t.id,d.user_id,r.actor_id)>0)
      AND (t.group_id IS NULL OR EXISTS(SELECT 1 FROM public.group_members g
        WHERE g.group_id=t.group_id AND g.user_id=d.user_id AND g.status='active')));
  UPDATE public.push_delivery_jobs j SET status='failed',error_code='retry_limit',lease_id=NULL,lease_until=NULL
    WHERE j.attempts>=6 AND (j.status='pending' OR (j.status='sending' AND j.lease_until<now()));
  RETURN QUERY WITH ready AS (
    SELECT j.id FROM public.push_delivery_jobs j
    WHERE (j.status='pending' AND j.next_attempt_at<=now()) OR (j.status='sending' AND j.lease_until<now())
    ORDER BY j.created_at,j.id FOR UPDATE SKIP LOCKED LIMIT least(greatest(p_limit,1),100)
  ), leased AS (
    UPDATE public.push_delivery_jobs j SET status='sending',attempts=j.attempts+1,
      lease_id=gen_random_uuid(),lease_until=now()+interval '2 minutes'
      FROM ready r WHERE j.id=r.id RETURNING j.*
  ) SELECT l.id,l.lease_id,l.notification_id,l.user_id,l.binding_id,n.related_tab_id,d.token
    FROM leased l JOIN public.push_device_bindings d ON d.installation_id=l.installation_id
      AND d.binding_id=l.binding_id AND d.user_id=l.user_id
    JOIN public.notifications n ON n.id=l.notification_id;
END; $$;

CREATE FUNCTION public.finish_reminder_push_v1(p_job_id uuid,p_lease_id uuid,p_outcome text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE job public.push_delivery_jobs%ROWTYPE;
BEGIN
  IF p_outcome IS NULL OR p_outcome NOT IN ('accepted','retry','unregistered','permanent') THEN
    RAISE EXCEPTION 'Invalid push outcome' USING ERRCODE='22023';
  END IF;
  SELECT * INTO job FROM public.push_delivery_jobs WHERE id=p_job_id AND lease_id=p_lease_id AND status='sending' FOR UPDATE;
  IF NOT FOUND THEN RETURN false; END IF;
  IF p_outcome='unregistered' THEN
    DELETE FROM public.push_device_bindings WHERE installation_id=job.installation_id AND binding_id=job.binding_id AND user_id=job.user_id;
  END IF;
  UPDATE public.push_delivery_jobs SET status=CASE WHEN p_outcome='accepted' THEN 'accepted'
      WHEN p_outcome='retry' AND attempts<6 THEN 'pending' ELSE 'failed' END,
    error_code=CASE WHEN p_outcome='accepted' THEN NULL ELSE p_outcome END,
    next_attempt_at=now()+make_interval(secs=>least(3600,(60*power(2,least(attempts,6)))::integer)),
    lease_id=NULL,lease_until=NULL WHERE id=job.id;
  RETURN true;
END; $$;
REVOKE ALL ON FUNCTION public.register_push_device_v1(uuid,uuid,text,boolean),public.revoke_push_device_v1(uuid,uuid),
  public.enqueue_reminder_push_v1(),public.claim_reminder_push_v1(integer),public.finish_reminder_push_v1(uuid,uuid,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.register_push_device_v1(uuid,uuid,text,boolean),public.revoke_push_device_v1(uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.claim_reminder_push_v1(integer),public.finish_reminder_push_v1(uuid,uuid,text) TO service_role;
