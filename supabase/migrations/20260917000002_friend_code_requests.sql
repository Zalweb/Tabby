-- Shareable Tabby IDs and authenticated friend-request workflow.
-- Friend IDs are intentionally random and are never derived from auth UUIDs.

-- ============================================================================
-- 1. SERVER-GENERATED SHAREABLE USER ID
-- ============================================================================

ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS friend_code TEXT;

CREATE OR REPLACE FUNCTION public.generate_friend_code()
RETURNS TEXT AS $$
DECLARE
    v_alphabet CONSTANT TEXT := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    v_code TEXT;
    v_index INTEGER;
    v_position INTEGER;
BEGIN
    LOOP
        v_code := 'TAB-';
        FOR v_position IN 1..6 LOOP
            v_index := 1 + floor(random() * length(v_alphabet))::INTEGER;
            v_code := v_code || substr(v_alphabet, v_index, 1);
        END LOOP;

        EXIT WHEN NOT EXISTS (
            SELECT 1 FROM public.users WHERE friend_code = v_code
        );
    END LOOP;

    RETURN v_code;
END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, pg_temp;

CREATE OR REPLACE FUNCTION public.assign_friend_code()
RETURNS TRIGGER AS $$
BEGIN
    -- Keep a previously issued code stable. Profile updates cannot rotate it.
    IF TG_OP = 'UPDATE'
       AND OLD.friend_code IS NOT NULL
       AND NEW.friend_code IS DISTINCT FROM OLD.friend_code THEN
        NEW.friend_code := OLD.friend_code;
    ELSIF NEW.friend_code IS NULL OR trim(NEW.friend_code) = '' THEN
        NEW.friend_code := public.generate_friend_code();
    END IF;

    NEW.friend_code := upper(trim(NEW.friend_code));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

DROP TRIGGER IF EXISTS trigger_assign_friend_code ON public.users;
CREATE TRIGGER trigger_assign_friend_code
    BEFORE INSERT OR UPDATE ON public.users
    FOR EACH ROW EXECUTE FUNCTION public.assign_friend_code();

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_friend_code
    ON public.users(friend_code);

UPDATE public.users
SET friend_code = public.generate_friend_code()
WHERE friend_code IS NULL OR trim(friend_code) = '';

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'users_friend_code_format'
          AND conrelid = 'public.users'::regclass
    ) THEN
        ALTER TABLE public.users
            ADD CONSTRAINT users_friend_code_format
            CHECK (friend_code ~ '^TAB-[A-HJ-NP-Z2-9]{6}$');
    END IF;
END $$;

ALTER TABLE public.users
    ALTER COLUMN friend_code SET NOT NULL;

ALTER FUNCTION public.generate_friend_code() SET search_path = public, pg_temp;
ALTER FUNCTION public.assign_friend_code() SET search_path = public, pg_temp;
REVOKE EXECUTE ON FUNCTION public.generate_friend_code() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.assign_friend_code() FROM PUBLIC, anon, authenticated;

-- ============================================================================
-- 2. SANITIZED FRIENDSHIP RESULT SHAPE
-- ============================================================================

-- Pending request responses expose names, avatars, and shareable IDs only.
-- Email, phone, payment accounts, QR URLs, and ledger fields are deliberately
-- absent from every function below.

CREATE OR REPLACE FUNCTION public.find_user_by_friend_code(p_friend_code TEXT)
RETURNS TABLE (
    id UUID,
    display_name TEXT,
    avatar_url TEXT,
    friend_code TEXT,
    relationship_status TEXT
) AS $$
DECLARE
    v_code TEXT;
    v_relationship_status TEXT;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    v_code := upper(regexp_replace(trim(coalesce(p_friend_code, '')), '^TAB-?', ''));
    IF v_code !~ '^[A-HJ-NP-Z2-9]{6}$' THEN
        RETURN;
    END IF;

    SELECT f.status
    INTO v_relationship_status
    FROM public.friendships f
    JOIN public.users target
      ON target.friend_code = 'TAB-' || v_code
    WHERE (f.requester_id = auth.uid() AND f.addressee_id = target.id)
       OR (f.addressee_id = auth.uid() AND f.requester_id = target.id)
    ORDER BY CASE f.status
        WHEN 'accepted' THEN 1
        WHEN 'pending' THEN 2
        WHEN 'blocked' THEN 3
        ELSE 4
    END, f.created_at DESC
    LIMIT 1;

    RETURN QUERY
    SELECT u.id,
           u.display_name,
           u.avatar_url,
           u.friend_code,
           coalesce(v_relationship_status, 'none')
    FROM public.users u
    WHERE u.friend_code = 'TAB-' || v_code
    LIMIT 1;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public, pg_temp;

CREATE OR REPLACE FUNCTION public.send_friend_request(p_friend_code TEXT)
RETURNS TABLE (
    id UUID,
    requester_id UUID,
    addressee_id UUID,
    status TEXT,
    created_at TIMESTAMPTZ,
    responded_at TIMESTAMPTZ,
    requester_display_name TEXT,
    requester_avatar_url TEXT,
    requester_friend_code TEXT,
    addressee_display_name TEXT,
    addressee_avatar_url TEXT,
    addressee_friend_code TEXT
) AS $$
DECLARE
    v_code TEXT;
    v_target_id UUID;
    v_existing public.friendships%ROWTYPE;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    v_code := upper(regexp_replace(trim(coalesce(p_friend_code, '')), '^TAB-?', ''));
    IF v_code !~ '^[A-HJ-NP-Z2-9]{6}$' THEN
        RAISE EXCEPTION 'Enter a valid Tabby ID';
    END IF;

    SELECT u.id INTO v_target_id
    FROM public.users u
    WHERE u.friend_code = 'TAB-' || v_code;

    IF v_target_id IS NULL THEN
        RAISE EXCEPTION 'No Tabby account was found for that ID';
    END IF;
    IF v_target_id = auth.uid() THEN
        RAISE EXCEPTION 'You cannot send a friend request to yourself';
    END IF;

    SELECT f.* INTO v_existing
    FROM public.friendships f
    WHERE (f.requester_id = auth.uid() AND f.addressee_id = v_target_id)
       OR (f.requester_id = v_target_id AND f.addressee_id = auth.uid())
    ORDER BY CASE f.status
        WHEN 'accepted' THEN 1
        WHEN 'pending' THEN 2
        WHEN 'blocked' THEN 3
        ELSE 4
    END, f.created_at DESC
    LIMIT 1;

    IF v_existing.id IS NOT NULL THEN
        IF v_existing.status = 'accepted' THEN
            RAISE EXCEPTION 'You are already connected with this person';
        ELSIF v_existing.status = 'blocked' THEN
            RAISE EXCEPTION 'This connection is unavailable';
        ELSIF v_existing.status = 'pending' THEN
            IF v_existing.requester_id = auth.uid() THEN
                RETURN QUERY
                SELECT f.id, f.requester_id, f.addressee_id, f.status,
                       f.created_at, f.responded_at,
                       requester.display_name, requester.avatar_url, requester.friend_code,
                       addressee.display_name, addressee.avatar_url, addressee.friend_code
                FROM public.friendships f
                JOIN public.users requester ON requester.id = f.requester_id
                JOIN public.users addressee ON addressee.id = f.addressee_id
                WHERE f.id = v_existing.id;
                RETURN;
            END IF;
            RAISE EXCEPTION 'This person has already sent you a request';
        ELSIF v_existing.requester_id = auth.uid() THEN
            UPDATE public.friendships
            SET status = 'pending', created_at = now(), responded_at = NULL
            WHERE id = v_existing.id;

            RETURN QUERY
            SELECT f.id, f.requester_id, f.addressee_id, f.status,
                   f.created_at, f.responded_at,
                   requester.display_name, requester.avatar_url, requester.friend_code,
                   addressee.display_name, addressee.avatar_url, addressee.friend_code
            FROM public.friendships f
            JOIN public.users requester ON requester.id = f.requester_id
            JOIN public.users addressee ON addressee.id = f.addressee_id
            WHERE f.id = v_existing.id;
            RETURN;
        END IF;
    END IF;

    INSERT INTO public.friendships (requester_id, addressee_id, status)
    VALUES (auth.uid(), v_target_id, 'pending')
    RETURNING * INTO v_existing;

    RETURN QUERY
    SELECT f.id, f.requester_id, f.addressee_id, f.status,
           f.created_at, f.responded_at,
           requester.display_name, requester.avatar_url, requester.friend_code,
           addressee.display_name, addressee.avatar_url, addressee.friend_code
    FROM public.friendships f
    JOIN public.users requester ON requester.id = f.requester_id
    JOIN public.users addressee ON addressee.id = f.addressee_id
    WHERE f.id = v_existing.id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

CREATE OR REPLACE FUNCTION public.list_friend_requests()
RETURNS TABLE (
    id UUID,
    requester_id UUID,
    addressee_id UUID,
    status TEXT,
    created_at TIMESTAMPTZ,
    responded_at TIMESTAMPTZ,
    requester_display_name TEXT,
    requester_avatar_url TEXT,
    requester_friend_code TEXT,
    addressee_display_name TEXT,
    addressee_avatar_url TEXT,
    addressee_friend_code TEXT
) AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    RETURN QUERY
    SELECT f.id, f.requester_id, f.addressee_id, f.status,
           f.created_at, f.responded_at,
           requester.display_name, requester.avatar_url, requester.friend_code,
           addressee.display_name, addressee.avatar_url, addressee.friend_code
    FROM public.friendships f
    JOIN public.users requester ON requester.id = f.requester_id
    JOIN public.users addressee ON addressee.id = f.addressee_id
    WHERE f.requester_id = auth.uid() OR f.addressee_id = auth.uid()
    ORDER BY f.created_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public, pg_temp;

CREATE OR REPLACE FUNCTION public.respond_friend_request(
    p_friendship_id UUID,
    p_accept BOOLEAN
)
RETURNS JSONB AS $$
DECLARE
    v_request public.friendships%ROWTYPE;
    v_tab_id UUID;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    SELECT f.* INTO v_request
    FROM public.friendships f
    WHERE f.id = p_friendship_id
      AND f.addressee_id = auth.uid()
      AND f.status = 'pending'
    FOR UPDATE;

    IF v_request.id IS NULL THEN
        RAISE EXCEPTION 'Friend request not found or already handled';
    END IF;

    UPDATE public.friendships
    SET status = CASE WHEN p_accept THEN 'accepted' ELSE 'declined' END,
        responded_at = now()
    WHERE id = v_request.id;

    IF p_accept THEN
        v_tab_id := public.get_or_create_bilateral_tab(
            v_request.requester_id,
            v_request.addressee_id
        );
    END IF;

    RETURN jsonb_build_object(
        'request_id', v_request.id,
        'status', CASE WHEN p_accept THEN 'accepted' ELSE 'declined' END,
        'tab_id', coalesce(v_tab_id::TEXT, '')
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

ALTER FUNCTION public.find_user_by_friend_code(TEXT) SET search_path = public, pg_temp;
ALTER FUNCTION public.send_friend_request(TEXT) SET search_path = public, pg_temp;
ALTER FUNCTION public.list_friend_requests() SET search_path = public, pg_temp;
ALTER FUNCTION public.respond_friend_request(UUID, BOOLEAN) SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.find_user_by_friend_code(TEXT) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.send_friend_request(TEXT) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.list_friend_requests() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.respond_friend_request(UUID, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.find_user_by_friend_code(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.send_friend_request(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_friend_requests() TO authenticated;
GRANT EXECUTE ON FUNCTION public.respond_friend_request(UUID, BOOLEAN) TO authenticated;

-- Pending friendships must not make private user rows visible through SELECT.
DROP POLICY IF EXISTS "Users can view their own profile and connected parties" ON public.users;
DROP POLICY IF EXISTS "Users can view their own profile and accepted connections" ON public.users;
CREATE POLICY "Users can view their own profile and accepted connections"
    ON public.users FOR SELECT
    TO authenticated
    USING (
        id = auth.uid()
        OR EXISTS (
            SELECT 1 FROM public.tabs t
            WHERE (t.user_a = auth.uid() AND t.user_b = public.users.id)
               OR (t.user_b = auth.uid() AND t.user_a = public.users.id)
        )
        OR EXISTS (
            SELECT 1 FROM public.tab_members tm1
            JOIN public.tab_members tm2 ON tm1.tab_id = tm2.tab_id
            WHERE tm1.user_id = auth.uid() AND tm2.user_id = public.users.id
        )
        OR EXISTS (
            SELECT 1 FROM public.group_members gm1
            JOIN public.group_members gm2 ON gm1.group_id = gm2.group_id
            WHERE gm1.user_id = auth.uid() AND gm2.user_id = public.users.id
              AND gm1.status = 'active' AND gm2.status = 'active'
        )
        OR EXISTS (
            SELECT 1 FROM public.friendships f
            WHERE f.status = 'accepted'
              AND ((f.requester_id = auth.uid() AND f.addressee_id = public.users.id)
                OR (f.addressee_id = auth.uid() AND f.requester_id = public.users.id))
        )
        OR EXISTS (
            SELECT 1 FROM public.contacts c
            WHERE c.owner_user_id = auth.uid() AND c.claimed_user_id = public.users.id
        )
    );

-- Requests are created/responded to through the authenticated RPCs. There is
-- intentionally no generic UPDATE policy that would allow either party to
-- rewrite friendship status or identities.
DROP POLICY IF EXISTS "Users can respond or modify their friendships" ON public.friendships;
DROP POLICY IF EXISTS "Users can delete their friendships" ON public.friendships;
DROP POLICY IF EXISTS "Requesters can cancel pending friendships" ON public.friendships;
CREATE POLICY "Requesters can cancel pending friendships"
    ON public.friendships FOR DELETE
    TO authenticated
    USING (requester_id = auth.uid() AND status = 'pending');
