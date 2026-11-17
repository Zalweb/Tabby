BEGIN;
ALTER TABLE public.users ADD COLUMN anonymized_at timestamptz;
ALTER TABLE public.account_deletion_requests ADD COLUMN reviewed_at timestamptz;
ALTER TABLE public.account_deletion_requests ADD COLUMN completed_at timestamptz;
CREATE TABLE public.account_deletion_objects (
  request_id uuid NOT NULL REFERENCES public.account_deletion_requests(id),
  bucket text NOT NULL CHECK(bucket IN ('profile-avatars','payment-methods')),
  path text NOT NULL, removed_at timestamptz,
  PRIMARY KEY(request_id,bucket,path)
);
ALTER TABLE public.account_deletion_objects ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.account_deletion_objects FROM PUBLIC,anon,authenticated;

-- A soft-deleted Auth identity and immutable financial UUIDs are retained.
-- Already-issued JWTs need a database check; banning/sign-out alone is insufficient.
CREATE FUNCTION public.account_is_active_v1() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
  SELECT NOT EXISTS(SELECT 1 FROM public.users WHERE id=auth.uid() AND anonymized_at IS NOT NULL);
$$;
CREATE FUNCTION public.tabby_pre_request() RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  IF NOT public.account_is_active_v1() THEN
    RAISE EXCEPTION 'Account no longer active' USING ERRCODE='42501';
  END IF;
END $$;
REVOKE ALL ON FUNCTION public.account_is_active_v1(),public.tabby_pre_request() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.account_is_active_v1(),public.tabby_pre_request() TO anon,authenticated,service_role;

CREATE FUNCTION public.block_deleted_actor_v1() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  PERFORM public.tabby_pre_request();
  IF TG_OP='INSERT' AND TG_TABLE_NAME IN ('notifications','reminders') THEN
    IF EXISTS(SELECT 1 FROM public.users WHERE id=NEW.recipient_user_id AND anonymized_at IS NOT NULL) THEN
      RAISE EXCEPTION 'Recipient account no longer active' USING ERRCODE='42501';
    END IF;
  END IF;
  IF TG_OP='INSERT' AND TG_TABLE_NAME='friendships' THEN
    IF EXISTS(SELECT 1 FROM public.users WHERE id IN (NEW.requester_id,NEW.addressee_id) AND anonymized_at IS NOT NULL) THEN
      RAISE EXCEPTION 'Connection account no longer active' USING ERRCODE='42501';
    END IF;
  END IF;
  IF TG_TABLE_NAME='users' AND current_setting('role',true) IN ('anon','authenticated') THEN
    IF (TG_OP='INSERT' AND NEW.anonymized_at IS NOT NULL) OR
       (TG_OP='UPDATE' AND NEW.anonymized_at IS DISTINCT FROM OLD.anonymized_at) THEN
      RAISE EXCEPTION 'Account lifecycle is service managed' USING ERRCODE='42501';
    END IF;
  END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END $$;
REVOKE ALL ON FUNCTION public.block_deleted_actor_v1() FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.protect_profile_identity_v1() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
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

-- Restrictive policies also cover Storage's direct database access, which does
-- not run the PostgREST pre-request hook. Trigger guards cover definer writes.
DO $$ DECLARE t record; existing text;
BEGIN
  FOR t IN SELECT n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE c.relkind IN ('r','p') AND c.relrowsecurity AND n.nspname IN ('public','storage') LOOP
    EXECUTE format('CREATE POLICY tabby_active_actor ON %I.%I AS RESTRICTIVE FOR ALL TO authenticated USING ((SELECT public.account_is_active_v1())) WITH CHECK ((SELECT public.account_is_active_v1()))',t.nspname,t.relname);
    IF t.nspname='public' THEN
      EXECUTE format('CREATE TRIGGER tabby_active_actor BEFORE INSERT OR UPDATE OR DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.block_deleted_actor_v1()',t.relname);
    END IF;
  END LOOP;
  IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticator') THEN
    SELECT value INTO existing FROM pg_db_role_setting s,
      LATERAL unnest(s.setconfig) value WHERE s.setrole=(SELECT oid FROM pg_roles WHERE rolname='authenticator')
      AND s.setdatabase IN (0,(SELECT oid FROM pg_database WHERE datname=current_database()))
      AND value LIKE 'pgrst.db_pre_request=%'
      AND value NOT IN ('pgrst.db_pre_request=','pgrst.db_pre_request=public.tabby_pre_request') LIMIT 1;
    IF existing IS NOT NULL THEN
      RAISE EXCEPTION 'Compose existing pre-request hook before installing privacy lifecycle guard';
    END IF;
    EXECUTE format('ALTER ROLE authenticator IN DATABASE %I SET pgrst.db_pre_request=%L',
      current_database(),'public.tabby_pre_request');
    NOTIFY pgrst,'reload config';
  END IF;
END $$;

CREATE FUNCTION public.review_account_deletion_v1(p_request_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE r public.account_deletion_requests;
BEGIN
  SELECT * INTO STRICT r FROM public.account_deletion_requests WHERE id=p_request_id FOR UPDATE;
  UPDATE public.account_deletion_requests SET reviewed_at=coalesce(reviewed_at,now()) WHERE id=r.id;
  RETURN jsonb_build_object('request_id',r.id,'account_id',r.user_id,'status',r.status,
    'auth_deleted',EXISTS(SELECT 1 FROM auth.users WHERE id=r.user_id AND deleted_at IS NOT NULL));
END $$;

CREATE FUNCTION public.prepare_account_deletion_v1(p_request_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE r public.account_deletion_requests;
BEGIN
  SELECT * INTO STRICT r FROM public.account_deletion_requests WHERE id=p_request_id FOR UPDATE;
  IF r.reviewed_at IS NULL THEN RAISE EXCEPTION 'Review required' USING ERRCODE='42501'; END IF;
  IF r.status='completed' THEN RETURN jsonb_build_object('status',r.status,'account_id',r.user_id); END IF;
  INSERT INTO public.account_deletion_objects(request_id,bucket,path)
    SELECT r.id,o.bucket_id,o.name FROM storage.objects o
    WHERE o.bucket_id IN ('profile-avatars','payment-methods') AND split_part(o.name,'/',1)=r.user_id::text
    ON CONFLICT DO NOTHING;
  UPDATE public.users SET anonymized_at=coalesce(anonymized_at,now()),display_name='Former member',
    email=NULL,phone=NULL,avatar_url=NULL,gcash_number=NULL,maya_number=NULL,qr_code_url=NULL WHERE id=r.user_id;
  UPDATE public.contacts SET display_name='Removed contact',email=NULL,phone=NULL WHERE owner_user_id=r.user_id;
  UPDATE public.payment_methods SET provider='Removed',display_name='Removed',account_label='',qr_storage_path=NULL,
    is_default=false,is_active=false WHERE owner_user_id=r.user_id;
  UPDATE public.payment_method_revisions SET snapshot=jsonb_build_object('id',method_id,'owner_user_id',owner_user_id,
    'revision',revision,'redacted',true) WHERE owner_user_id=r.user_id;
  DELETE FROM public.payment_method_operations WHERE actor_id=r.user_id;
  DELETE FROM public.connection_operations WHERE owner_id=r.user_id;
  DELETE FROM public.connection_preferences WHERE owner_id=r.user_id;
  DELETE FROM public.push_device_bindings WHERE user_id=r.user_id;
  UPDATE public.push_delivery_jobs SET status='cancelled',lease_id=NULL,lease_until=NULL
    WHERE user_id=r.user_id AND status IN ('pending','sending');
  UPDATE public.notifications SET title='Removed account notice',body='' WHERE recipient_user_id=r.user_id;
  UPDATE public.reminders SET status='cancelled' WHERE (created_by=r.user_id OR recipient_user_id=r.user_id) AND status='scheduled';
  DELETE FROM public.friendships WHERE requester_id=r.user_id OR addressee_id=r.user_id;
  UPDATE public.account_deletion_requests SET status='processing' WHERE id=r.id;
  RETURN jsonb_build_object('status','processing','account_id',r.user_id);
END $$;

CREATE FUNCTION public.pending_deletion_objects_v1(p_request_id uuid) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
  SELECT coalesce(jsonb_agg(jsonb_build_object('bucket',bucket,'path',path) ORDER BY bucket,path),'[]'::jsonb)
    FROM (SELECT bucket,path FROM public.account_deletion_objects
      WHERE request_id=p_request_id AND removed_at IS NULL ORDER BY bucket,path LIMIT 100) page;
$$;
CREATE FUNCTION public.acknowledge_deletion_object_v1(p_request_id uuid,p_bucket text,p_path text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  IF EXISTS(SELECT 1 FROM storage.objects WHERE bucket_id=p_bucket AND name=p_path) THEN
    RAISE EXCEPTION 'Object removal not confirmed' USING ERRCODE='55000'; END IF;
  UPDATE public.account_deletion_objects SET removed_at=coalesce(removed_at,now())
    WHERE request_id=p_request_id AND bucket=p_bucket AND path=p_path;
  RETURN FOUND;
END $$;

CREATE FUNCTION public.finish_account_deletion_v1(p_request_id uuid) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE r public.account_deletion_requests;
BEGIN
  SELECT * INTO STRICT r FROM public.account_deletion_requests WHERE id=p_request_id FOR UPDATE;
  IF r.status='completed' THEN RETURN true; END IF;
  IF r.status<>'processing' OR r.reviewed_at IS NULL OR
    NOT EXISTS(SELECT 1 FROM public.users WHERE id=r.user_id AND anonymized_at IS NOT NULL) OR
    NOT EXISTS(SELECT 1 FROM auth.users WHERE id=r.user_id AND deleted_at IS NOT NULL) OR
    EXISTS(SELECT 1 FROM auth.sessions WHERE user_id=r.user_id) OR
    EXISTS(SELECT 1 FROM public.account_deletion_objects WHERE request_id=r.id AND removed_at IS NULL) OR
    EXISTS(SELECT 1 FROM storage.objects WHERE bucket_id IN ('profile-avatars','payment-methods')
      AND split_part(name,'/',1)=r.user_id::text) THEN
    RAISE EXCEPTION 'Deletion processing incomplete' USING ERRCODE='55000';
  END IF;
  UPDATE public.account_deletion_requests SET status='completed',completed_at=now() WHERE id=r.id;
  RETURN true;
END $$;
REVOKE ALL ON FUNCTION public.review_account_deletion_v1(uuid),public.prepare_account_deletion_v1(uuid),
 public.pending_deletion_objects_v1(uuid),public.acknowledge_deletion_object_v1(uuid,text,text),
 public.finish_account_deletion_v1(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.review_account_deletion_v1(uuid),public.prepare_account_deletion_v1(uuid),
 public.pending_deletion_objects_v1(uuid),public.acknowledge_deletion_object_v1(uuid,text,text),
 public.finish_account_deletion_v1(uuid) TO service_role;

CREATE FUNCTION public.reject_anonymized_participant_v1() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND EXISTS(SELECT 1 FROM public.users WHERE id=NEW.user_id AND anonymized_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Cannot add a new share for an inactive account' USING ERRCODE='42501'; END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.reject_anonymized_participant_v1() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER reject_anonymized_participant BEFORE INSERT ON public.transaction_participants
  FOR EACH ROW EXECUTE FUNCTION public.reject_anonymized_participant_v1();

CREATE FUNCTION public.export_private_page_v1(p_section text,p_after uuid DEFAULT NULL,p_limit integer DEFAULT 50)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor uuid:=auth.uid(); records jsonb; last_id uuid; more boolean;
BEGIN
  PERFORM public.tabby_pre_request();
  IF actor IS NULL THEN RAISE EXCEPTION 'Sign in required' USING ERRCODE='42501'; END IF;
  IF p_section IS NULL OR p_section NOT IN ('receiving_methods','connections','contacts','notifications','reminders') OR
    p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN
    RAISE EXCEPTION 'Invalid private export page' USING ERRCODE='22023'; END IF;
  WITH scoped AS (
    SELECT p.id,jsonb_build_object('id',p.id,'provider',p.provider,'display_name',p.display_name,
      'account_label',p.account_label,'is_active',p.is_active,'is_default',p.is_default) record
      FROM public.payment_methods p WHERE p.owner_user_id=actor AND p_section='receiving_methods'
    UNION ALL SELECT c.id,jsonb_build_object('id',c.id,'display_name',c.display_name,'phone',c.phone,'email',c.email)
      FROM public.contacts c WHERE c.owner_user_id=actor AND p_section='contacts'
    UNION ALL SELECT c.owner_id,jsonb_build_object('id',c.owner_id,'nicknames',c.nicknames,'archived_tab_ids',c.archived_tab_ids)
      FROM public.connection_preferences c WHERE c.owner_id=actor AND p_section='connections'
    UNION ALL SELECT n.id,jsonb_build_object('id',n.id,'type',n.notification_type,'title',n.title,'body',n.body,
      'created_at',n.created_at,'is_read',n.is_read) FROM public.notifications n
      WHERE n.recipient_user_id=actor AND p_section='notifications'
    UNION ALL SELECT r.id,jsonb_build_object('id',r.id,'transaction_id',r.transaction_id,'type',r.reminder_type,
      'scheduled_for',r.scheduled_for,'status',r.status) FROM public.reminders r
      WHERE r.recipient_user_id=actor AND p_section='reminders'
  ), page_window AS (SELECT * FROM scoped WHERE p_after IS NULL OR id>p_after ORDER BY id LIMIT p_limit+1),
  page AS (SELECT * FROM page_window ORDER BY id LIMIT p_limit)
  SELECT coalesce(jsonb_agg(record ORDER BY id),'[]'::jsonb),
    (SELECT id FROM page ORDER BY id DESC LIMIT 1),(SELECT count(*)>p_limit FROM page_window)
    INTO records,last_id,more FROM page;
  RETURN jsonb_build_object('version',1,'account_id',actor,'section',p_section,'records',records,
    'next_cursor',CASE WHEN more THEN last_id ELSE NULL END);
END $$;
REVOKE ALL ON FUNCTION public.export_private_page_v1(text,uuid,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.export_private_page_v1(text,uuid,integer) TO authenticated;
CREATE OR REPLACE FUNCTION public.is_tab_member(p_tab_id UUID, p_user_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    IF NOT public.account_is_active_v1() THEN RETURN FALSE; END IF;
    IF p_user_id IS NULL OR p_tab_id IS NULL THEN
        RETURN FALSE;
    END IF;

    RETURN EXISTS (
        SELECT 1 FROM public.tab_members
        WHERE tab_id = p_tab_id AND user_id = p_user_id
    ) OR EXISTS (
        SELECT 1 FROM public.tabs
        WHERE id = p_tab_id AND (user_a = p_user_id OR user_b = p_user_id)
    ) OR EXISTS (
        SELECT 1 FROM public.tabs t
        JOIN public.group_members gm ON t.group_id = gm.group_id
        WHERE t.id = p_tab_id AND gm.user_id = p_user_id AND gm.status = 'active'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;
ALTER FUNCTION public.is_tab_member(uuid,uuid) SET search_path=pg_catalog,public;
CREATE OR REPLACE FUNCTION public.is_group_member(p_group_id UUID, p_user_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    IF NOT public.account_is_active_v1() THEN RETURN FALSE; END IF;
    IF p_user_id IS NULL OR p_group_id IS NULL THEN
        RETURN FALSE;
    END IF;

    RETURN EXISTS (
        SELECT 1 FROM public.group_members
        WHERE group_id = p_group_id AND user_id = p_user_id AND status = 'active'
    ) OR EXISTS (
        SELECT 1 FROM public.groups
        WHERE id = p_group_id AND created_by = p_user_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;
ALTER FUNCTION public.is_group_member(uuid,uuid) SET search_path=pg_catalog,public;
CREATE OR REPLACE FUNCTION public.is_group_admin(p_group_id UUID, p_user_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    IF NOT public.account_is_active_v1() THEN RETURN FALSE; END IF;
    IF p_user_id IS NULL OR p_group_id IS NULL THEN
        RETURN FALSE;
    END IF;

    RETURN EXISTS (
        SELECT 1 FROM public.group_members
        WHERE group_id = p_group_id AND user_id = p_user_id AND role = 'admin' AND status = 'active'
    ) OR EXISTS (
        SELECT 1 FROM public.groups
        WHERE id = p_group_id AND created_by = p_user_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;
ALTER FUNCTION public.is_group_admin(uuid,uuid) SET search_path=pg_catalog,public;

-- Guarded replacements for pre-existing privacy RPCs follow below.

-- Intentionally limited personal-data export. Shared ledger/media need a
-- separate paginated export contract; do not expose arbitrary row JSON.
CREATE OR REPLACE FUNCTION public.export_account_data_v1()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public AS $$
DECLARE actor uuid := auth.uid(); result jsonb;
BEGIN
  PERFORM public.tabby_pre_request();
  IF actor IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;
  SELECT jsonb_build_object(
    'version', 1, 'account_id', actor, 'generated_at', statement_timestamp(),
    'scope', 'profile_and_owned_contacts',
    'excluded', jsonb_build_array('shared_ledger', 'payment_methods',
      'media', 'notifications', 'authentication_records', 'local_drafts'),
    'profile', (SELECT jsonb_build_object(
      'id', u.id, 'display_name', u.display_name, 'email', u.email,
      'phone', u.phone, 'created_at', u.created_at)
      FROM public.users u WHERE u.id = actor),
    'contacts', COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id', c.id, 'display_name', c.display_name, 'email', c.email,
      'phone', c.phone, 'created_at', c.created_at) ORDER BY c.id)
      FROM public.contacts c WHERE c.owner_user_id = actor), '[]'::jsonb)
  ) INTO result;
  RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.export_account_data_v1() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.export_account_data_v1() TO authenticated;

-- No target-account argument: the server chooses scope from the JWT subject.
-- Explicit projections avoid exporting storage URLs or newly added columns.
CREATE OR REPLACE FUNCTION public.export_ledger_page_v1(
  p_section text, p_after uuid DEFAULT NULL, p_limit integer DEFAULT 50
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public AS $$
DECLARE actor uuid := auth.uid(); rows jsonb; last_id uuid; has_more boolean;
BEGIN
  PERFORM public.tabby_pre_request();
  IF actor IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;
  IF p_section IS NULL OR p_section NOT IN ('tabs', 'expenses', 'shares', 'payments')
    OR p_limit IS NULL OR p_limit < 1 OR p_limit > 100 THEN
    RAISE EXCEPTION 'Invalid export section or page size' USING ERRCODE = '22023';
  END IF;
  WITH authorized_tabs AS (
    SELECT t.id FROM public.tabs t
    WHERE t.user_a = actor OR t.user_b = actor OR EXISTS (
      SELECT 1 FROM public.tab_members m WHERE m.tab_id = t.id AND m.user_id = actor)
  ), scoped AS (
    SELECT t.id, jsonb_build_object('id',t.id, 'type',t.tab_type,
      'status',t.status, 'group_id',t.group_id, 'user_a',t.user_a,
      'user_b',t.user_b, 'created_at',t.created_at) AS record
    FROM public.tabs t JOIN authorized_tabs a ON a.id = t.id
    WHERE p_section = 'tabs'
    UNION ALL
    SELECT t.id, jsonb_build_object('id',t.id, 'tab_id',t.tab_id,
      'created_by',t.created_by, 'description',t.description,
      'category',t.category, 'status',t.status, 'total_amount_centavos',t.total_amount_centavos,
      'currency',t.currency, 'transaction_date',t.transaction_date,
      'due_date',t.due_date, 'created_at',t.created_at)
    FROM public.transactions t JOIN authorized_tabs a ON a.id = t.tab_id
    WHERE p_section = 'expenses'
    UNION ALL
    SELECT s.id, jsonb_build_object('id',s.id, 'transaction_id',s.transaction_id,
      'user_id',s.user_id, 'contact_id',s.contact_id,
      'role',s.participant_role, 'share_amount_centavos',s.share_amount_centavos,
      'acknowledged',s.acknowledged, 'acknowledged_at',s.acknowledged_at)
    FROM public.transaction_participants s
    JOIN public.transactions t ON t.id = s.transaction_id
    JOIN authorized_tabs a ON a.id = t.tab_id
    WHERE p_section = 'shares'
    UNION ALL
    SELECT p.id, jsonb_build_object('id',p.id, 'tab_id',p.tab_id,
      'submitted_by',p.submitted_by, 'recipient_user_id',p.recipient_user_id,
      'amount_centavos',p.amount_centavos, 'payment_method',p.payment_method,
      'note',p.note, 'status',p.status, 'submitted_at',p.submitted_at,
      'confirmed_by',p.confirmed_by, 'confirmed_at',p.confirmed_at)
    FROM public.payments p JOIN authorized_tabs a ON a.id = p.tab_id
    WHERE p_section = 'payments'
  ), page_window AS (
    SELECT * FROM scoped WHERE p_after IS NULL OR id > p_after
    ORDER BY id LIMIT p_limit + 1
  ), page AS (
    SELECT * FROM page_window ORDER BY id LIMIT p_limit
  )
  SELECT COALESCE((SELECT jsonb_agg(record ORDER BY id) FROM page),'[]'::jsonb),
    (SELECT id FROM page ORDER BY id DESC LIMIT 1),
    (SELECT count(*) > p_limit FROM page_window)
  INTO rows, last_id, has_more;
  RETURN jsonb_build_object('version',1, 'account_id',actor,
    'section',p_section, 'records',rows,
    'next_cursor',CASE WHEN has_more THEN last_id ELSE NULL END,
    'generated_at',statement_timestamp(),
    'consistency','Each page is a current read, not a whole-export snapshot.');
END $$;
REVOKE ALL ON FUNCTION public.export_ledger_page_v1(text,uuid,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.export_ledger_page_v1(text,uuid,integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_account_deletion_request_v1()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public AS $$
DECLARE actor uuid := auth.uid(); result jsonb;
BEGIN
  PERFORM public.tabby_pre_request();
  IF actor IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;
  SELECT jsonb_build_object('id',r.id,'account_id',actor,
    'requested_at',r.requested_at,'status',r.status)
  INTO result FROM public.account_deletion_requests r WHERE r.user_id = actor;
  RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_account_deletion_request_v1() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_account_deletion_request_v1() TO authenticated;

CREATE OR REPLACE FUNCTION public.request_account_deletion_v1()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public AS $$
DECLARE actor uuid := auth.uid(); request public.account_deletion_requests;
BEGIN
  PERFORM public.tabby_pre_request();
  IF actor IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;
  -- AMR timestamps describe actual authentication, unlike refreshed-token iat.
  -- Claims come from the verified JWT at the PostgREST boundary.
  IF NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(COALESCE(auth.jwt()->'amr', '[]'::jsonb)) m
    WHERE m->>'method' IN ('password', 'otp', 'oauth', 'totp', 'sso/saml')
      AND CASE WHEN m->>'timestamp' ~ '^[0-9]{1,12}$'
        THEN (m->>'timestamp')::bigint
          BETWEEN extract(epoch FROM statement_timestamp())::bigint - 300
          AND extract(epoch FROM statement_timestamp())::bigint + 30
        ELSE false END
  ) THEN
    RAISE EXCEPTION 'Sign in again before requesting account deletion' USING ERRCODE = '42501';
  END IF;
  INSERT INTO public.account_deletion_requests(user_id) VALUES (actor)
    ON CONFLICT (user_id) DO NOTHING;
  SELECT * INTO STRICT request FROM public.account_deletion_requests WHERE user_id = actor;
  RETURN jsonb_build_object('id', request.id, 'account_id', actor,
    'requested_at', request.requested_at, 'status', request.status);
END $$;
REVOKE ALL ON FUNCTION public.request_account_deletion_v1() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_account_deletion_v1() TO authenticated;

COMMIT;
