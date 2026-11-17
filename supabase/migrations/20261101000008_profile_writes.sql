-- Core profile writes acknowledge the persisted row. Auth owns email;
-- saved payment methods own receiving destinations. No history is rewritten.
CREATE OR REPLACE FUNCTION public.protect_profile_identity_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF NEW.email IS DISTINCT FROM (CASE WHEN TG_OP='UPDATE' THEN OLD.email ELSE NULL END)
     AND NEW.email IS DISTINCT FROM (SELECT email FROM auth.users WHERE id=NEW.id) THEN
    RAISE EXCEPTION 'Profile email must match Auth' USING ERRCODE='42501';
  END IF;
  IF current_setting('role',true) IN ('anon','authenticated') THEN
    IF TG_OP='INSERT' THEN
      IF coalesce(NEW.gcash_number,'')<>'' OR coalesce(NEW.maya_number,'')<>'' OR coalesce(NEW.qr_code_url,'')<>'' THEN
        RAISE EXCEPTION 'Use saved receiving methods' USING ERRCODE='42501';
      END IF;
    ELSIF NEW.gcash_number IS DISTINCT FROM OLD.gcash_number
       OR NEW.maya_number IS DISTINCT FROM OLD.maya_number
       OR NEW.qr_code_url IS DISTINCT FROM OLD.qr_code_url THEN
      RAISE EXCEPTION 'Use saved receiving methods' USING ERRCODE='42501';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS protect_profile_identity_v1 ON public.users;
CREATE TRIGGER protect_profile_identity_v1 BEFORE INSERT OR UPDATE ON public.users
FOR EACH ROW EXECUTE FUNCTION public.protect_profile_identity_v1();
REVOKE ALL ON FUNCTION public.protect_profile_identity_v1() FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.update_profile_v1(p_changes jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_actor uuid:=auth.uid(); v_row public.users%ROWTYPE; v_phone text; v_name text;
BEGIN
  IF v_actor IS NULL THEN RAISE EXCEPTION 'Sign in required' USING ERRCODE='42501'; END IF;
  IF p_changes IS NULL OR jsonb_typeof(p_changes)<>'object'
    OR p_changes - ARRAY['display_name','phone','avatar_url'] <> '{}'::jsonb THEN
    RAISE EXCEPTION 'Unsupported profile fields' USING ERRCODE='22023';
  END IF;
  SELECT * INTO v_row FROM public.users WHERE id=v_actor FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Profile unavailable' USING ERRCODE='P0002'; END IF;
  IF p_changes ? 'display_name' THEN
    v_name:=btrim(p_changes->>'display_name');
    IF jsonb_typeof(p_changes->'display_name')<>'string' OR v_name IS NULL OR length(v_name) NOT BETWEEN 1 AND 80 THEN
      RAISE EXCEPTION 'Invalid display name' USING ERRCODE='22023';
    END IF;
    v_row.display_name:=v_name;
  END IF;
  IF p_changes ? 'phone' THEN
    v_phone:=public.normalize_ph_mobile_v1(p_changes->>'phone');
    IF jsonb_typeof(p_changes->'phone')<>'string' OR v_phone IS NULL THEN
      RAISE EXCEPTION 'Invalid mobile number' USING ERRCODE='22023';
    END IF;
    v_row.phone:=v_phone;
  END IF;
  IF p_changes ? 'avatar_url' THEN
    IF jsonb_typeof(p_changes->'avatar_url')<>'string' OR length(p_changes->>'avatar_url')>2048 THEN
      RAISE EXCEPTION 'Invalid avatar' USING ERRCODE='22023';
    END IF;
    v_row.avatar_url:=p_changes->>'avatar_url';
  END IF;
  UPDATE public.users SET display_name=v_row.display_name, phone=v_row.phone,
    avatar_url=v_row.avatar_url, updated_at=now() WHERE id=v_actor RETURNING * INTO v_row;
  RETURN to_jsonb(v_row);
END;
$$;
REVOKE ALL ON FUNCTION public.update_profile_v1(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_profile_v1(jsonb) TO authenticated;
REVOKE UPDATE ON public.users FROM anon,authenticated;

-- Email confirmation or an OAuth metadata refresh must not restore old signup
-- name/phone/avatar over the user's subsequently saved profile edits.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  UPDATE public.users SET email=NEW.email,updated_at=now() WHERE id=NEW.id;
  IF FOUND THEN RETURN NEW; END IF;
  INSERT INTO public.users(id,email,phone,display_name,avatar_url)
  VALUES(NEW.id,NEW.email,coalesce(nullif(NEW.phone,''),NEW.raw_user_meta_data->>'phone'),
    coalesce(nullif(NEW.raw_user_meta_data->>'display_name',''),nullif(NEW.raw_user_meta_data->>'name',''),
      split_part(coalesce(NEW.email,'User'),'@',1)),NEW.raw_user_meta_data->>'avatar_url');
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC,anon,authenticated;
