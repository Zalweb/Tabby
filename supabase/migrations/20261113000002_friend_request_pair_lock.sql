-- Serialize same-pair friend-request creation across concurrent devices.
-- Preserve existing rows, RPC shape and explicit recipient consent.
BEGIN;

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

    -- Serialize the absence check too: a row lock cannot protect a pair
    -- whose first request has not been inserted. Both directions use one key.
    PERFORM pg_advisory_xact_lock(hashtextextended(
        'friend-request:' || least(auth.uid(), v_target_id)::text || ':' ||
        greatest(auth.uid(), v_target_id)::text, 0
    ));

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
            UPDATE public.friendships AS f
            SET status = 'pending', created_at = now(), responded_at = NULL
            WHERE f.id = v_existing.id;

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

REVOKE EXECUTE ON FUNCTION public.send_friend_request(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.send_friend_request(TEXT) TO authenticated;
COMMIT;
