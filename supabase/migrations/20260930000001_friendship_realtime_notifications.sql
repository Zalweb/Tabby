-- Migration: 20260930000001_friendship_realtime_notifications.sql
-- Enables real-time database notifications and publication for friendship updates and friend requests.

-- 1. Create or replace the friendship notification trigger function
CREATE OR REPLACE FUNCTION public.handle_friendship_notification()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
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
        WHERE t.is_group = false
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

-- 2. Attach trigger to friendships
DROP TRIGGER IF EXISTS trg_friendship_notification ON public.friendships;
CREATE TRIGGER trg_friendship_notification
AFTER INSERT OR UPDATE ON public.friendships
FOR EACH ROW
EXECUTE FUNCTION public.handle_friendship_notification();

-- 3. Add notifications to realtime publication and set full replica identity
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'notifications'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
    END IF;
END $$;

ALTER TABLE public.notifications REPLICA IDENTITY FULL;
