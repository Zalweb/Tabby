-- A direct INSERT must never manufacture recipient consent. The legacy policy
-- checked only requester_id, so clients could insert status='accepted' and gain
-- friend-only profile/receiving/media access without a recipient decision.
-- Preserve existing rows; all client creation/decision goes through the guarded
-- SECURITY DEFINER RPCs. Trusted owner/service imports retain their privileges.
BEGIN;
DROP POLICY IF EXISTS "Users can request friendship" ON public.friendships;
REVOKE INSERT ON public.friendships FROM PUBLIC, anon, authenticated;

-- Preserve the existing RPC contract. Qualify the resend UPDATE key to avoid
-- ambiguity with the RETURNS TABLE id output variable (SQLSTATE 42702).
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

-- Acceptance notifications used a nonexistent tabs.is_group column. Resolve
-- the canonical tab before the status trigger and link its actual identity.
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

    IF p_accept THEN
        v_tab_id := public.get_or_create_bilateral_tab(
            v_request.requester_id,
            v_request.addressee_id
        );
    END IF;

    UPDATE public.friendships
    SET status = CASE WHEN p_accept THEN 'accepted' ELSE 'declined' END,
        responded_at = now()
    WHERE id = v_request.id;

    RETURN jsonb_build_object(
        'request_id', v_request.id,
        'status', CASE WHEN p_accept THEN 'accepted' ELSE 'declined' END,
        'tab_id', coalesce(v_tab_id::TEXT, '')
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

CREATE OR REPLACE FUNCTION public.handle_friendship_notification()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_requester_name TEXT;
    v_addressee_name TEXT;
    v_tab_id UUID;
BEGIN
    IF (TG_OP = 'INSERT' AND NEW.status = 'pending') THEN
        SELECT display_name INTO v_requester_name
        FROM public.users WHERE id = NEW.requester_id;

        INSERT INTO public.notifications (
            recipient_user_id,
            notification_type,
            title,
            body,
            is_read,
            created_at
        ) VALUES (
            NEW.addressee_id,
            'friend_request',
            'New Friend Request',
            coalesce(v_requester_name, 'A user') || ' sent you a friend request.',
            false,
            now()
        );
    ELSIF (TG_OP = 'UPDATE' AND NEW.status = 'accepted' AND (OLD.status IS DISTINCT FROM 'accepted')) THEN
        SELECT display_name INTO v_addressee_name
        FROM public.users WHERE id = NEW.addressee_id;

        -- Find or get bilateral tab id
        SELECT t.id INTO v_tab_id
        FROM public.tabs t
        JOIN public.tab_members tm1 ON tm1.tab_id = t.id AND tm1.user_id = NEW.requester_id
        JOIN public.tab_members tm2 ON tm2.tab_id = t.id AND tm2.user_id = NEW.addressee_id
        WHERE t.tab_type = 'individual'
          AND t.status = 'active'
          AND t.user_a = least(NEW.requester_id, NEW.addressee_id)
          AND t.user_b = greatest(NEW.requester_id, NEW.addressee_id)
        LIMIT 1;

        INSERT INTO public.notifications (
            recipient_user_id,
            notification_type,
            related_tab_id,
            title,
            body,
            is_read,
            created_at
        ) VALUES (
            NEW.requester_id,
            'friend_request',
            v_tab_id,
            'Friend Request Accepted',
            coalesce(v_addressee_name, 'Your friend') || ' accepted your friend request.',
            false,
            now()
        );
    END IF;
    RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.respond_friend_request(UUID, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.respond_friend_request(UUID, BOOLEAN) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.handle_friendship_notification() FROM PUBLIC, anon, authenticated;

-- Explicitly attach the repaired trigger, including schema-snapshot bootstraps
-- that lacked the historical friendship-notification migration.
DROP TRIGGER IF EXISTS trg_friendship_notification ON public.friendships;
CREATE TRIGGER trg_friendship_notification
AFTER INSERT OR UPDATE ON public.friendships
FOR EACH ROW EXECUTE FUNCTION public.handle_friendship_notification();
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime' AND schemaname = 'public'
          AND tablename = 'notifications'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
    END IF;
END $$;
ALTER TABLE public.notifications REPLICA IDENTITY FULL;
COMMIT;
