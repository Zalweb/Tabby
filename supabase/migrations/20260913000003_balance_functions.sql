-- Tabby Database Migration: 20260913000003_balance_functions.sql
-- Description: Stored PostgreSQL functions and RPCs for the Balance Calculation Engine.
-- Specifications: AGENTS.md Section 8 (Balance Calculation Engine & Mathematical Specification).
-- Perspective Formula:
--   Net Balance_A = Sum(Obligations Owed to A)
--                 - Sum(Obligations Owed by A)
--                 - Sum(Confirmed Payments Received by A)
--                 + Sum(Confirmed Payments Made by A)
-- Integer Centavos Standard: All calculations operate in 64-bit BIGINT centavos.

-- ============================================================================
-- 1. HELPER: RESOLVE PAYER FOR A TRANSACTION
-- Returns the user_id of the person who paid for the transaction.
-- If a participant has role = 'payer', that user is the payer.
-- Otherwise, transactions.created_by is the default payer.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_transaction_payer_id(p_transaction_id UUID)
RETURNS UUID AS $$
DECLARE
    v_payer_id UUID;
BEGIN
    -- Check if an explicit payer participant exists
    SELECT user_id INTO v_payer_id
    FROM public.transaction_participants
    WHERE transaction_id = p_transaction_id AND participant_role = 'payer' AND user_id IS NOT NULL
    LIMIT 1;

    -- Fall back to transaction creator
    IF v_payer_id IS NULL THEN
        SELECT created_by INTO v_payer_id
        FROM public.transactions
        WHERE id = p_transaction_id;
    END IF;

    RETURN v_payer_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- ============================================================================
-- 2. CORE RPC: GET NET BALANCE FOR A TAB FROM USER PERSPECTIVE
-- Formula from AGENTS.md Section 8.1:
--   + > 0: Other party owes User A ("You're owed")
--   - < 0: User A owes other party ("You owe")
--   = 0  : Settled up ("Bayad na!")
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_net_balance(p_tab_id UUID, p_user_id UUID)
RETURNS BIGINT AS $$
DECLARE
    v_obligations_owed_to_user BIGINT := 0;
    v_obligations_owed_by_user BIGINT := 0;
    v_payments_received BIGINT := 0;
    v_payments_made BIGINT := 0;
    v_net_balance BIGINT := 0;
BEGIN
    IF p_tab_id IS NULL OR p_user_id IS NULL THEN
        RETURN 0;
    END IF;

    -- 1. Obligations Owed TO User A:
    -- User A paid (payer = p_user_id), and other participants owe their share.
    SELECT COALESCE(SUM(tp.share_amount_centavos), 0)
    INTO v_obligations_owed_to_user
    FROM public.transactions t
    JOIN public.transaction_participants tp ON tp.transaction_id = t.id
    WHERE t.tab_id = p_tab_id
      AND t.status NOT IN ('cancelled', 'disputed')
      AND public.get_transaction_payer_id(t.id) = p_user_id
      AND tp.participant_role IN ('debtor', 'beneficiary')
      AND (tp.user_id IS NULL OR tp.user_id <> p_user_id);

    -- 2. Obligations Owed BY User A:
    -- Someone else paid (payer <> p_user_id), and User A is debtor for their share.
    SELECT COALESCE(SUM(tp.share_amount_centavos), 0)
    INTO v_obligations_owed_by_user
    FROM public.transactions t
    JOIN public.transaction_participants tp ON tp.transaction_id = t.id
    WHERE t.tab_id = p_tab_id
      AND t.status NOT IN ('cancelled', 'disputed')
      AND public.get_transaction_payer_id(t.id) <> p_user_id
      AND tp.participant_role IN ('debtor', 'beneficiary')
      AND tp.user_id = p_user_id;

    -- 3. Confirmed Payments Received by User A:
    -- In a bilateral or multi-party tab, confirmed payments where User A was the confirmed recipient.
    SELECT COALESCE(SUM(p.amount_centavos), 0)
    INTO v_payments_received
    FROM public.payments p
    WHERE p.tab_id = p_tab_id
      AND p.status = 'confirmed'
      AND (
          p.confirmed_by = p_user_id OR
          (p.submitted_by <> p_user_id AND p.confirmed_by IS NULL)
      );

    -- 4. Confirmed Payments Made by User A:
    -- Payments submitted by User A that have been confirmed.
    SELECT COALESCE(SUM(p.amount_centavos), 0)
    INTO v_payments_made
    FROM public.payments p
    WHERE p.tab_id = p_tab_id
      AND p.status = 'confirmed'
      AND p.submitted_by = p_user_id;

    -- Net Balance = (Owed to A) - (Owed by A) - (Received by A) + (Made by A)
    v_net_balance := v_obligations_owed_to_user - v_obligations_owed_by_user - v_payments_received + v_payments_made;

    RETURN v_net_balance;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- ============================================================================
-- 3. RPC: GET TAB SUMMARY WITH MASCOT EMOTION STATE
-- Returns rich summary JSON for Screen 3 (Individual Tab Detail).
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_tab_summary(p_tab_id UUID, p_user_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_net_balance BIGINT := 0;
    v_obligations_owed_to_user BIGINT := 0;
    v_obligations_owed_by_user BIGINT := 0;
    v_payments_received BIGINT := 0;
    v_payments_made BIGINT := 0;
    v_mascot_state TEXT := 'IDLE_NEUTRAL';
    v_status_label TEXT := 'All settled up';
    v_tab_type TEXT;
    v_tab_status TEXT;
BEGIN
    SELECT tab_type, status INTO v_tab_type, v_tab_status
    FROM public.tabs
    WHERE id = p_tab_id;

    IF v_tab_type IS NULL THEN
        RETURN jsonb_build_object('error', 'Tab not found');
    END IF;

    -- Calculate breakdown
    SELECT COALESCE(SUM(tp.share_amount_centavos), 0)
    INTO v_obligations_owed_to_user
    FROM public.transactions t
    JOIN public.transaction_participants tp ON tp.transaction_id = t.id
    WHERE t.tab_id = p_tab_id
      AND t.status NOT IN ('cancelled', 'disputed')
      AND public.get_transaction_payer_id(t.id) = p_user_id
      AND tp.participant_role IN ('debtor', 'beneficiary')
      AND (tp.user_id IS NULL OR tp.user_id <> p_user_id);

    SELECT COALESCE(SUM(tp.share_amount_centavos), 0)
    INTO v_obligations_owed_by_user
    FROM public.transactions t
    JOIN public.transaction_participants tp ON tp.transaction_id = t.id
    WHERE t.tab_id = p_tab_id
      AND t.status NOT IN ('cancelled', 'disputed')
      AND public.get_transaction_payer_id(t.id) <> p_user_id
      AND tp.participant_role IN ('debtor', 'beneficiary')
      AND tp.user_id = p_user_id;

    SELECT COALESCE(SUM(p.amount_centavos), 0)
    INTO v_payments_received
    FROM public.payments p
    WHERE p.tab_id = p_tab_id
      AND p.status = 'confirmed'
      AND (
          p.confirmed_by = p_user_id OR
          (p.submitted_by <> p_user_id AND p.confirmed_by IS NULL)
      );

    SELECT COALESCE(SUM(p.amount_centavos), 0)
    INTO v_payments_made
    FROM public.payments p
    WHERE p.tab_id = p_tab_id
      AND p.status = 'confirmed'
      AND p.submitted_by = p_user_id;

    v_net_balance := v_obligations_owed_to_user - v_obligations_owed_by_user - v_payments_received + v_payments_made;

    -- Determine Mascot State per Section 4 FSM
    IF v_net_balance > 0 THEN
        v_mascot_state := 'USER_IS_OWED';
        v_status_label := 'You are owed';
    ELSIF v_net_balance < 0 THEN
        v_mascot_state := 'USER_OWES';
        v_status_label := 'You owe';
    ELSE
        v_mascot_state := 'SLEEPING';
        v_status_label := 'Bayad na! All settled';
    END IF;

    RETURN jsonb_build_object(
        'tab_id', p_tab_id,
        'user_id', p_user_id,
        'tab_type', v_tab_type,
        'tab_status', v_tab_status,
        'net_balance_centavos', v_net_balance,
        'obligations_owed_to_user_centavos', v_obligations_owed_to_user,
        'obligations_owed_by_user_centavos', v_obligations_owed_by_user,
        'payments_received_centavos', v_payments_received,
        'payments_made_centavos', v_payments_made,
        'mascot_state', v_mascot_state,
        'status_label', v_status_label,
        'currency', 'PHP'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- ============================================================================
-- 4. RPC: GET USER DASHBOARD SUMMARY
-- Returns aggregate financial standing for Screen 1 (Home Dashboard):
-- "You owe", "You're owed", and global mascot mood.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_user_dashboard_summary(p_user_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_tab_record RECORD;
    v_tab_balance BIGINT := 0;
    v_total_you_owe BIGINT := 0;
    v_total_you_are_owed BIGINT := 0;
    v_active_tabs_count INT := 0;
    v_settled_tabs_count INT := 0;
    v_mascot_state TEXT := 'IDLE_NEUTRAL';
BEGIN
    IF p_user_id IS NULL THEN
        RETURN jsonb_build_object('error', 'User ID is required');
    END IF;

    -- Iterate through all distinct tabs the user is part of
    FOR v_tab_record IN
        SELECT DISTINCT t.id, t.status
        FROM public.tabs t
        LEFT JOIN public.tab_members tm ON tm.tab_id = t.id
        WHERE (tm.user_id = p_user_id OR t.user_a = p_user_id OR t.user_b = p_user_id)
    LOOP
        v_tab_balance := public.get_net_balance(v_tab_record.id, p_user_id);

        IF v_tab_balance > 0 THEN
            v_total_you_are_owed := v_total_you_are_owed + v_tab_balance;
            v_active_tabs_count := v_active_tabs_count + 1;
        ELSIF v_tab_balance < 0 THEN
            v_total_you_owe := v_total_you_owe + ABS(v_tab_balance);
            v_active_tabs_count := v_active_tabs_count + 1;
        ELSE
            v_settled_tabs_count := v_settled_tabs_count + 1;
        END IF;
    END LOOP;

    -- Global mascot state determination
    IF v_total_you_owe > 0 THEN
        v_mascot_state := 'USER_OWES';
    ELSIF v_total_you_are_owed > 0 THEN
        v_mascot_state := 'USER_IS_OWED';
    ELSE
        v_mascot_state := 'SLEEPING';
    END IF;

    RETURN jsonb_build_object(
        'user_id', p_user_id,
        'total_you_owe_centavos', v_total_you_owe,
        'total_you_are_owed_centavos', v_total_you_are_owed,
        'active_tabs_count', v_active_tabs_count,
        'settled_tabs_count', v_settled_tabs_count,
        'mascot_state', v_mascot_state,
        'currency', 'PHP'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- ============================================================================
-- 5. RPC: GET OR CREATE BILATERAL TAB
-- Enforces canonical bilateral tab rule (Section 7.3 Rule 2) and <5s speed directive.
-- Finds an active bilateral tab between User A and User B, or atomically creates one.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_or_create_bilateral_tab(p_user_a UUID, p_user_b UUID)
RETURNS UUID AS $$
DECLARE
    v_tab_id UUID;
    v_first_user UUID;
    v_second_user UUID;
BEGIN
    IF p_user_a IS NULL OR p_user_b IS NULL THEN
        RAISE EXCEPTION 'Both user IDs must be non-null';
    END IF;

    IF p_user_a = p_user_b THEN
        RAISE EXCEPTION 'Cannot create bilateral tab with oneself';
    END IF;

    -- Canonical ordering: LEAST and GREATEST
    IF p_user_a < p_user_b THEN
        v_first_user := p_user_a;
        v_second_user := p_user_b;
    ELSE
        v_first_user := p_user_b;
        v_second_user := p_user_a;
    END IF;

    -- Check for existing active bilateral tab
    SELECT id INTO v_tab_id
    FROM public.tabs
    WHERE tab_type = 'individual'
      AND status = 'active'
      AND user_a = v_first_user
      AND user_b = v_second_user
    LIMIT 1;

    -- If found, return it
    IF v_tab_id IS NOT NULL THEN
        RETURN v_tab_id;
    END IF;

    -- Create new canonical bilateral tab
    BEGIN
        INSERT INTO public.tabs (tab_type, status, user_a, user_b)
        VALUES ('individual', 'active', v_first_user, v_second_user)
        RETURNING id INTO v_tab_id;

        -- Insert both members into tab_members
        INSERT INTO public.tab_members (tab_id, user_id, role)
        VALUES 
            (v_tab_id, v_first_user, 'participant'),
            (v_tab_id, v_second_user, 'participant')
        ON CONFLICT DO NOTHING;
    EXCEPTION WHEN unique_violation THEN
        SELECT id INTO v_tab_id
        FROM public.tabs
        WHERE tab_type = 'individual'
          AND status = 'active'
          AND user_a = v_first_user
          AND user_b = v_second_user
        LIMIT 1;
    END;

    RETURN v_tab_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- 6. RPC: CLAIM CONTACT (ADR-007)
-- Explicit claim and acknowledge flow: links virtual contact to registered user.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.claim_contact(p_contact_id UUID, p_claimed_user_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    v_contact RECORD;
BEGIN
    SELECT * INTO v_contact
    FROM public.contacts
    WHERE id = p_contact_id;

    IF v_contact.id IS NULL THEN
        RAISE EXCEPTION 'Contact not found';
    END IF;

    IF v_contact.claim_status = 'claimed' THEN
        RAISE EXCEPTION 'Contact has already been claimed';
    END IF;

    -- Update contact record
    UPDATE public.contacts
    SET claimed_user_id = p_claimed_user_id,
        claim_status = 'claimed',
        claimed_at = now()
    WHERE id = p_contact_id;

    -- Update tab members where contact_id was referenced
    UPDATE public.tab_members
    SET user_id = p_claimed_user_id
    WHERE contact_id = p_contact_id AND user_id IS NULL;

    -- Update transaction participants where contact_id was referenced
    UPDATE public.transaction_participants
    SET user_id = p_claimed_user_id
    WHERE contact_id = p_contact_id AND user_id IS NULL;

    -- Log activity
    INSERT INTO public.activity_logs (
        actor_user_id,
        event_type,
        metadata
    ) VALUES (
        p_claimed_user_id,
        'CONTACT_CLAIMED',
        jsonb_build_object(
            'contact_id', p_contact_id,
            'contact_display_name', v_contact.display_name,
            'owner_user_id', v_contact.owner_user_id
        )
    );

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
