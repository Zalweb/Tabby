-- Production reconciliation: repairs defects that blocked expense, payment and
-- reminder writes on the hosted database.

-- 1. Notification types written by trigger functions were never allowed by the
--    CHECK constraint, so the insert (and its parent expense) aborted.
ALTER TABLE public.notifications
    DROP CONSTRAINT IF EXISTS notifications_notification_type_check;

ALTER TABLE public.notifications
    ADD CONSTRAINT notifications_notification_type_check
    CHECK (notification_type IN (
        'debt_created', 'debt_acknowledged', 'amount_proposed', 'amount_changed',
        'payment_submitted', 'payment_confirmed', 'reminder_due', 'reminder_overdue',
        'manual_nudge', 'friend_request', 'group_invite', 'report_filed',
        'expense_added', 'tab_reminder'
    ));

-- 2. send_tab_reminder wrote activity_logs columns that do not exist on the
--    deployed schema (user_id/action_type/description vs actor_user_id/event_type).
CREATE OR REPLACE FUNCTION public.send_tab_reminder(
    p_tab_id UUID,
    p_recipient_user_id UUID,
    p_title TEXT,
    p_body TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_current_user_id UUID := auth.uid();
    v_notif_id UUID;
BEGIN
    IF v_current_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    IF p_recipient_user_id = v_current_user_id THEN
        RAISE EXCEPTION 'Cannot send reminder to yourself';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.tab_members
        WHERE tab_id = p_tab_id AND user_id = v_current_user_id
    ) THEN
        RAISE EXCEPTION 'Current user is not a member of this tab';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.tab_members
        WHERE tab_id = p_tab_id AND user_id = p_recipient_user_id
    ) THEN
        RAISE EXCEPTION 'Recipient is not a member of this tab';
    END IF;

    INSERT INTO public.notifications (
        recipient_user_id, notification_type, related_tab_id,
        title, body, is_read, created_at
    ) VALUES (
        p_recipient_user_id, 'tab_reminder', p_tab_id,
        p_title, p_body, false, now()
    ) RETURNING id INTO v_notif_id;

    INSERT INTO public.activity_logs (
        actor_user_id, tab_id, event_type, metadata
    ) VALUES (
        v_current_user_id, p_tab_id, 'REMINDER_SENT',
        jsonb_build_object(
            'recipient_id', p_recipient_user_id,
            'title', p_title,
            'body', p_body
        )
    );

    RETURN v_notif_id;
END;
$$;

REVOKE ALL ON FUNCTION public.send_tab_reminder(UUID, UUID, TEXT, TEXT)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.send_tab_reminder(UUID, UUID, TEXT, TEXT)
    TO authenticated;

-- 3. Internal money helpers must not be executable by unauthenticated roles.
REVOKE ALL ON FUNCTION public.calculate_user_tab_balance_unchecked(UUID, UUID)
    FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.validate_transaction_split(UUID)
    FROM PUBLIC, anon;
