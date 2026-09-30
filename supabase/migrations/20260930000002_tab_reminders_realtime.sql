-- Migration: 20260930000002_tab_reminders_realtime.sql
-- Enables real-time database notifications and reminders of tabs for the user who owes (debtor).

-- ============================================================================
-- 1. SEND TAB REMINDER RPC
-- ============================================================================
-- Allows a tab member to send a friendly reminder notification to a debtor member.
-- Security Definer ensures controlled creation of notifications with strict membership checks.

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
    v_is_sender_member BOOLEAN;
    v_is_recipient_member BOOLEAN;
    v_notif_id UUID;
    v_sender_name TEXT;
BEGIN
    IF v_current_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    IF p_recipient_user_id = v_current_user_id THEN
        RAISE EXCEPTION 'Cannot send reminder to yourself';
    END IF;

    -- Verify sender is member of tab
    SELECT EXISTS (
        SELECT 1 FROM public.tab_members
        WHERE tab_id = p_tab_id AND user_id = v_current_user_id
    ) INTO v_is_sender_member;

    IF NOT v_is_sender_member THEN
        RAISE EXCEPTION 'Current user is not a member of this tab';
    END IF;

    -- Verify recipient is member of tab
    SELECT EXISTS (
        SELECT 1 FROM public.tab_members
        WHERE tab_id = p_tab_id AND user_id = p_recipient_user_id
    ) INTO v_is_recipient_member;

    IF NOT v_is_recipient_member THEN
        RAISE EXCEPTION 'Recipient is not a member of this tab';
    END IF;

    -- Insert notification for the recipient
    INSERT INTO public.notifications (
        recipient_user_id,
        notification_type,
        related_tab_id,
        title,
        body,
        is_read,
        created_at
    ) VALUES (
        p_recipient_user_id,
        'tab_reminder',
        p_tab_id,
        p_title,
        p_body,
        false,
        now()
    ) RETURNING id INTO v_notif_id;

    -- Also record in activity log for auditability
    INSERT INTO public.activity_logs (
        tab_id,
        user_id,
        action_type,
        description,
        metadata
    ) VALUES (
        p_tab_id,
        v_current_user_id,
        'reminder_sent',
        p_title,
        jsonb_build_object(
            'recipient_id', p_recipient_user_id,
            'title', p_title,
            'body', p_body
        )
    );

    RETURN v_notif_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.send_tab_reminder(UUID, UUID, TEXT, TEXT) TO authenticated;

-- ============================================================================
-- 2. RLS POLICY: ALLOW TAB MEMBERS TO QUEUE REMINDER NOTIFICATIONS
-- ============================================================================

DROP POLICY IF EXISTS "Tab members can queue reminders" ON public.notifications;
CREATE POLICY "Tab members can queue reminders"
    ON public.notifications FOR INSERT
    TO authenticated
    WITH CHECK (
        notification_type IN ('tab_reminder', 'manual_nudge')
        AND recipient_user_id != auth.uid()
        AND EXISTS (
            SELECT 1 FROM public.tab_members tm_sender
            JOIN public.tab_members tm_recipient ON tm_recipient.tab_id = tm_sender.tab_id
            WHERE tm_sender.tab_id = notifications.related_tab_id
              AND tm_sender.user_id = auth.uid()
              AND tm_recipient.user_id = notifications.recipient_user_id
        )
    );

-- ============================================================================
-- 3. AUTOMATIC EXPENSE NOTIFICATION TRIGGER FOR DEBTOR USERS
-- ============================================================================
-- When an expense is recorded, all debtor participants who are registered users
-- receive an immediate real-time notification informing them of their share.

CREATE OR REPLACE FUNCTION public.handle_expense_debtor_notification()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_tab_id UUID;
    v_tx_title TEXT;
    v_tx_type TEXT;
    v_total_amount BIGINT;
    v_created_by UUID;
    v_payer_name TEXT;
    v_formatted_total TEXT;
    v_formatted_share TEXT;
BEGIN
    IF (TG_OP = 'INSERT' AND NEW.participant_role = 'debtor' AND NEW.user_id IS NOT NULL) THEN
        -- Get transaction details
        SELECT tab_id, description, transaction_type, total_amount_centavos, created_by
        INTO v_tab_id, v_tx_title, v_tx_type, v_total_amount, v_created_by
        FROM public.transactions
        WHERE id = NEW.transaction_id;

        -- Don't notify the creator if they are also debtor
        IF (NEW.user_id = v_created_by) THEN
            RETURN NEW;
        END IF;

        -- Get creator/payer name
        SELECT display_name INTO v_payer_name
        FROM public.users
        WHERE id = v_created_by;

        v_formatted_total := '₱' || to_char((v_total_amount / 100.0), 'FM999,999,990.00');
        v_formatted_share := '₱' || to_char((NEW.share_amount_centavos / 100.0), 'FM999,999,990.00');

        INSERT INTO public.notifications (
            recipient_user_id,
            notification_type,
            related_tab_id,
            related_transaction_id,
            title,
            body,
            is_read,
            created_at
        ) VALUES (
            NEW.user_id,
            'expense_added',
            v_tab_id,
            NEW.transaction_id,
            'New Expense: ' || coalesce(v_tx_title, 'Shared expense'),
            coalesce(v_payer_name, 'A friend') || ' paid ' || v_formatted_total || '. Your share is ' || v_formatted_share || '.',
            false,
            now()
        );
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_expense_debtor_notification ON public.transaction_participants;
CREATE TRIGGER trg_expense_debtor_notification
AFTER INSERT ON public.transaction_participants
FOR EACH ROW
EXECUTE FUNCTION public.handle_expense_debtor_notification();

-- ============================================================================
-- 4. REPLICA IDENTITY AND REALTIME PUBLICATION
-- ============================================================================

ALTER TABLE public.notifications REPLICA IDENTITY FULL;
ALTER TABLE public.transactions REPLICA IDENTITY FULL;
ALTER TABLE public.transaction_participants REPLICA IDENTITY FULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'notifications'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'transaction_participants'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.transaction_participants;
    END IF;
END $$;
