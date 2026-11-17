-- AUTH-004: canonicalize new/explicitly changed profile phones. No bulk rewrite,
-- identity merging or guessed repair of historical duplicates is performed.
CREATE FUNCTION public.normalize_ph_mobile_v1(p_phone text) RETURNS text
LANGUAGE plpgsql IMMUTABLE SET search_path=public,pg_temp AS $$
DECLARE compact text;
BEGIN
  IF p_phone IS NULL OR btrim(p_phone) !~ '^\+?[0-9 ()-]+$' THEN RETURN NULL; END IF;
  compact:=regexp_replace(btrim(p_phone),'[ ()-]','','g');
  IF compact ~ '^09[0-9]{9}$' THEN RETURN '+63'||substring(compact from 2); END IF;
  IF compact ~ '^9[0-9]{9}$' THEN RETURN '+63'||compact; END IF;
  IF compact ~ '^\+?639[0-9]{9}$' THEN RETURN CASE WHEN left(compact,1)='+' THEN compact ELSE '+'||compact END; END IF;
  RETURN NULL;
END; $$;
CREATE FUNCTION public.canonical_profile_phone_v1() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE canonical text;
BEGIN
  IF TG_OP='UPDATE' AND NEW.phone IS NOT DISTINCT FROM OLD.phone THEN RETURN NEW; END IF;
  IF NEW.phone IS NULL OR btrim(NEW.phone)='' THEN RETURN NEW; END IF;
  canonical:=public.normalize_ph_mobile_v1(NEW.phone);
  IF canonical IS NULL THEN RAISE EXCEPTION 'Invalid Philippine mobile number' USING ERRCODE='22023'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('profile-phone:'||canonical,0));
  IF EXISTS(SELECT 1 FROM public.users u WHERE u.id<>NEW.id AND public.normalize_ph_mobile_v1(u.phone)=canonical) THEN
    RAISE EXCEPTION 'users_phone_canonical_conflict' USING ERRCODE='23505';
  END IF;
  NEW.phone:=canonical;RETURN NEW;
END; $$;
CREATE TRIGGER canonical_profile_phone BEFORE INSERT OR UPDATE OF phone ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.canonical_profile_phone_v1();
CREATE OR REPLACE FUNCTION public.is_phone_available(p_phone text,p_user_id uuid DEFAULT NULL)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE canonical text:=public.normalize_ph_mobile_v1(p_phone);
BEGIN
  IF canonical IS NULL THEN RETURN false; END IF;
  RETURN NOT EXISTS(SELECT 1 FROM public.users u WHERE public.normalize_ph_mobile_v1(u.phone)=canonical
    AND NOT(u.id IS NOT DISTINCT FROM auth.uid() AND p_user_id IS NOT DISTINCT FROM auth.uid()));
END; $$;
REVOKE ALL ON FUNCTION public.canonical_profile_phone_v1() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.is_phone_available(text,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_phone_available(text,uuid) TO anon,authenticated;
