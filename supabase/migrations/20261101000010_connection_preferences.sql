-- Private labels and reversible Connections views never edit shared money.
CREATE TABLE public.connection_preferences (
  owner_id uuid PRIMARY KEY REFERENCES public.users(id),
  revision bigint NOT NULL DEFAULT 0,
  nicknames jsonb NOT NULL DEFAULT '{}'::jsonb,
  archived_tab_ids uuid[] NOT NULL DEFAULT '{}'
);
CREATE TABLE public.connection_operations (
  owner_id uuid NOT NULL REFERENCES public.users(id), operation_id uuid NOT NULL,
  command jsonb NOT NULL, result jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(owner_id,operation_id)
);
ALTER TABLE public.connection_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.connection_operations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.connection_preferences,public.connection_operations FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.connection_preferences_v1() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE result jsonb;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in required' USING ERRCODE='42501'; END IF;
  SELECT jsonb_build_object('revision',revision,'nicknames',nicknames,'archived_tab_ids',to_jsonb(archived_tab_ids))
    INTO result FROM public.connection_preferences WHERE owner_id=auth.uid();
  RETURN coalesce(result,'{"revision":0,"nicknames":{},"archived_tab_ids":[]}'::jsonb);
END; $$;

CREATE FUNCTION public.change_connection_v1(p_operation_id uuid,p_command jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE actor uuid:=auth.uid(); previous public.connection_operations%ROWTYPE;
  prefs public.connection_preferences%ROWTYPE; target uuid; action text; nickname text; result jsonb;
BEGIN
  IF actor IS NULL THEN RAISE EXCEPTION 'Sign in required' USING ERRCODE='42501'; END IF;
  IF p_operation_id IS NULL OR p_command IS NULL OR jsonb_typeof(p_command)<>'object' THEN
    RAISE EXCEPTION 'Invalid connection command' USING ERRCODE='22023'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('connections:'||actor::text,0));
  SELECT * INTO previous FROM public.connection_operations WHERE owner_id=actor AND operation_id=p_operation_id;
  IF FOUND THEN
    IF previous.command<>p_command THEN RAISE EXCEPTION 'Operation payload changed' USING ERRCODE='22023'; END IF;
    RETURN previous.result;
  END IF;
  IF actor IS DISTINCT FROM (p_command->>'owner_id')::uuid THEN
    RAISE EXCEPTION 'Account changed' USING ERRCODE='42501'; END IF;
  IF p_command - ARRAY['owner_id','action','target_id','nickname','expected_revision']<>'{}'::jsonb
    OR jsonb_typeof(p_command->'expected_revision') IS DISTINCT FROM 'number'
    OR (p_command->>'expected_revision') !~ '^[0-9]+$' THEN
    RAISE EXCEPTION 'Invalid connection fields' USING ERRCODE='22023'; END IF;
  INSERT INTO public.connection_preferences(owner_id) VALUES(actor) ON CONFLICT DO NOTHING;
  SELECT * INTO prefs FROM public.connection_preferences WHERE owner_id=actor FOR UPDATE;
  IF prefs.revision<>(p_command->>'expected_revision')::bigint THEN
    RAISE EXCEPTION 'Connections changed. Reload and retry.' USING ERRCODE='40001'; END IF;
  action:=p_command->>'action'; target:=(p_command->>'target_id')::uuid;
  IF target IS NULL THEN RAISE EXCEPTION 'Missing target' USING ERRCODE='22023'; END IF;
  IF action='nickname' THEN
    IF target=actor OR NOT EXISTS(SELECT 1 FROM public.friendships f WHERE f.status='accepted'
      AND ((f.requester_id=actor AND f.addressee_id=target) OR (f.requester_id=target AND f.addressee_id=actor))) THEN
      RAISE EXCEPTION 'Accepted friend required' USING ERRCODE='42501'; END IF;
    nickname:=btrim(p_command->>'nickname');
    IF jsonb_typeof(p_command->'nickname') IS DISTINCT FROM 'string' OR length(nickname)>80 THEN
      RAISE EXCEPTION 'Invalid nickname' USING ERRCODE='22023'; END IF;
    IF nickname='' THEN prefs.nicknames:=prefs.nicknames-target::text;
    ELSE prefs.nicknames:=jsonb_set(prefs.nicknames,ARRAY[target::text],to_jsonb(nickname)); END IF;
  ELSIF action IN ('archive','restore') THEN
    IF NOT EXISTS(SELECT 1 FROM public.tabs t JOIN public.tab_members tm ON tm.tab_id=t.id AND tm.user_id=actor
       WHERE t.id=target AND t.tab_type='group' AND t.status='active'
         AND (t.group_id IS NULL OR EXISTS(SELECT 1 FROM public.group_members gm
           WHERE gm.group_id=t.group_id AND gm.user_id=actor AND gm.status='active'))) THEN
      RAISE EXCEPTION 'Active group member required' USING ERRCODE='42501'; END IF;
    prefs.archived_tab_ids:=array_remove(prefs.archived_tab_ids,target);
    IF action='archive' THEN prefs.archived_tab_ids:=array_append(prefs.archived_tab_ids,target); END IF;
  ELSIF action='unfriend' THEN
    IF target=actor THEN RAISE EXCEPTION 'Invalid friend' USING ERRCODE='22023'; END IF;
    DELETE FROM public.friendships f WHERE f.status='accepted'
      AND ((f.requester_id=actor AND f.addressee_id=target) OR (f.requester_id=target AND f.addressee_id=actor));
  ELSE RAISE EXCEPTION 'Unsupported action' USING ERRCODE='22023';
  END IF;
  UPDATE public.connection_preferences SET nicknames=prefs.nicknames,
    archived_tab_ids=prefs.archived_tab_ids,revision=revision+1 WHERE owner_id=actor;
  result:=public.connection_preferences_v1();
  INSERT INTO public.connection_operations(owner_id,operation_id,command,result) VALUES(actor,p_operation_id,p_command,result);
  RETURN result;
END; $$;
REVOKE ALL ON FUNCTION public.connection_preferences_v1(),public.change_connection_v1(uuid,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.connection_preferences_v1(),public.change_connection_v1(uuid,jsonb) TO authenticated;

CREATE FUNCTION public.protect_shared_archive_v1() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status AND (NEW.status='archived' OR OLD.status='archived')
     AND current_setting('role',true) IN ('anon','authenticated') THEN
    RAISE EXCEPTION 'Use private Connections archive' USING ERRCODE='42501'; END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER protect_shared_archive BEFORE UPDATE OF status ON public.tabs
FOR EACH ROW EXECUTE FUNCTION public.protect_shared_archive_v1();
REVOKE ALL ON FUNCTION public.protect_shared_archive_v1() FROM PUBLIC,anon,authenticated;

-- Bind core profile/social writes to the initiating actor even if a client's
-- bearer token changes while an asynchronous HTTP request is being prepared.
CREATE FUNCTION public.update_profile_v2(p_expected_owner uuid,p_changes jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  IF auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM p_expected_owner THEN
    RAISE EXCEPTION 'Account changed' USING ERRCODE='42501'; END IF;
  RETURN public.update_profile_v1(p_changes);
END; $$;
REVOKE ALL ON FUNCTION public.update_profile_v1(jsonb),public.update_profile_v2(uuid,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.update_profile_v2(uuid,jsonb) TO authenticated;

CREATE FUNCTION public.remove_friend_v2(p_expected_owner uuid,p_friend_user_id uuid) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  IF auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM p_expected_owner THEN
    RAISE EXCEPTION 'Account changed' USING ERRCODE='42501'; END IF;
  IF p_friend_user_id IS NULL OR p_friend_user_id=auth.uid() THEN RETURN false; END IF;
  DELETE FROM public.friendships f WHERE f.status='accepted' AND
    ((f.requester_id=auth.uid() AND f.addressee_id=p_friend_user_id) OR
     (f.requester_id=p_friend_user_id AND f.addressee_id=auth.uid()));
  RETURN true;
END; $$;
REVOKE ALL ON FUNCTION public.remove_friend_v2(uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.remove_friend_v2(uuid,uuid) TO authenticated;
DO $$ BEGIN
  IF to_regprocedure('public.remove_friend(uuid)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.remove_friend(uuid) FROM PUBLIC,anon,authenticated;
  END IF;
END $$;
