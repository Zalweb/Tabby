-- Private, immutable profile images. Only the current reference is shared.
INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
VALUES('profile-avatars','profile-avatars',false,2097152,ARRAY['image/png'])
ON CONFLICT(id) DO UPDATE SET public=false,file_size_limit=2097152,allowed_mime_types=ARRAY['image/png'];

CREATE FUNCTION public.can_read_profile_avatar_v1(p_name text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
  SELECT auth.uid() IS NOT NULL AND (
    split_part(p_name,'/',1)=auth.uid()::text
    OR EXISTS(SELECT 1 FROM public.users u WHERE u.avatar_url='avatar:'||p_name AND (
      EXISTS(SELECT 1 FROM public.friendships f WHERE f.status='accepted' AND
        ((f.requester_id=auth.uid() AND f.addressee_id=u.id) OR
         (f.addressee_id=auth.uid() AND f.requester_id=u.id)))
      OR EXISTS(SELECT 1 FROM public.tabs t
        JOIN public.tab_members me ON me.tab_id=t.id AND me.user_id=auth.uid()
        JOIN public.tab_members peer ON peer.tab_id=t.id AND peer.user_id=u.id
        WHERE t.status='active' AND (t.group_id IS NULL OR
          (EXISTS(SELECT 1 FROM public.group_members gm WHERE gm.group_id=t.group_id AND gm.user_id=auth.uid() AND gm.status='active')
           AND EXISTS(SELECT 1 FROM public.group_members gm WHERE gm.group_id=t.group_id AND gm.user_id=u.id AND gm.status='active'))))
    ))
  );
$$;
REVOKE ALL ON FUNCTION public.can_read_profile_avatar_v1(text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_read_profile_avatar_v1(text) TO authenticated;
CREATE POLICY profile_avatar_read ON storage.objects FOR SELECT TO authenticated
USING(bucket_id='profile-avatars' AND public.can_read_profile_avatar_v1(name));
CREATE POLICY profile_avatar_insert ON storage.objects FOR INSERT TO authenticated
WITH CHECK(bucket_id='profile-avatars' AND name ~ ('^'||auth.uid()::text||'/[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.png$'));
-- No UPDATE or DELETE grants through a policy. Existing immutable objects are
-- retained for explicit cleanup/privacy work; removal only clears the profile.

CREATE FUNCTION public.validate_profile_avatar_v1() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  IF TG_OP='UPDATE' AND NEW.avatar_url IS NOT DISTINCT FROM OLD.avatar_url THEN RETURN NEW; END IF;
  IF coalesce(NEW.avatar_url,'') IN ('','asset:mascot','asset:cat_cool','asset:camera_snap') THEN RETURN NEW; END IF;
  -- Initial OAuth metadata can retain its legacy external reference. Clients
  -- render initials for external URLs; they never issue untrusted image HTTP.
  IF TG_OP='INSERT' AND NEW.avatar_url LIKE 'https://%' THEN RETURN NEW; END IF;
  IF NEW.avatar_url !~ ('^avatar:'||NEW.id::text||'/[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.png$')
    OR NOT EXISTS(SELECT 1 FROM storage.objects WHERE bucket_id='profile-avatars' AND name=substring(NEW.avatar_url from 8)) THEN
    RAISE EXCEPTION 'Upload an owned profile photo first' USING ERRCODE='22023';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER validate_profile_avatar BEFORE INSERT OR UPDATE OF avatar_url ON public.users
FOR EACH ROW EXECUTE FUNCTION public.validate_profile_avatar_v1();
REVOKE ALL ON FUNCTION public.validate_profile_avatar_v1() FROM PUBLIC,anon,authenticated;
