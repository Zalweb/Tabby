-- Tabby Database Migration: 20260917000001_authz_hardening.sql
-- Description: Enforces authenticated ownership and append-only financial mutations.
-- Scope: RLS policy hardening, security-definer RPC authorization, and tamper guards.

-- ============================================================================
-- 1. RLS POLICY HARDENING
-- ============================================================================

-- A user can only create a direct tab containing themselves, or a group tab for
-- a group they created. Bilateral tabs are normally created through the guarded
-- get_or_create_bilateral_tab RPC below.
DROP POLICY IF EXISTS "Authenticated users can create tabs" ON public.tabs;
CREATE POLICY "Authenticated users can create tabs"
    ON public.tabs FOR INSERT
    TO authenticated
    WITH CHECK (
        (
            tab_type IN ('individual', 'shared_couple')
            AND user_a IS NOT NULL
            AND user_b IS NOT NULL
            AND user_a <> user_b
            AND (user_a = auth.uid() OR user_b = auth.uid())
        )
        OR (
            tab_type = 'group'
            AND group_id IS NOT NULL
            AND EXISTS (
                SELECT 1
                FROM public.groups g
                WHERE g.id = group_id
                  AND g.created_by = auth.uid()
            )
        )
    );

-- Joining an arbitrary group is not a valid invitation flow. Only a group
-- admin can add another member; a group creator may add themselves while the
-- group is being created.
DROP POLICY IF EXISTS "Group admins or creator can add members" ON public.group_members;
CREATE POLICY "Group admins or creator can add members"
    ON public.group_members FOR INSERT
    TO authenticated
    WITH CHECK (
        public.is_group_admin(group_id, auth.uid())
        OR (
            user_id = auth.uid()
            AND EXISTS (
                SELECT 1
                FROM public.groups g
                WHERE g.id = group_id
                  AND g.created_by = auth.uid()
            )
        )
    );

-- Tab membership is controlled by a tab admin. A group creator may insert the
-- first member for a newly-created group tab.
DROP POLICY IF EXISTS "Tab members or creator can add tab members" ON public.tab_members;
CREATE POLICY "Tab members or creator can add tab members"
    ON public.tab_members FOR INSERT
    TO authenticated
    WITH CHECK (
        (
            EXISTS (
                SELECT 1
                FROM public.tab_members tm
                WHERE tm.tab_id = tab_id
                  AND tm.user_id = auth.uid()
                  AND tm.role = 'admin'
            )
        )
        OR (
            user_id = auth.uid()
            AND EXISTS (
                SELECT 1
                FROM public.tabs t
                JOIN public.groups g ON g.id = t.group_id
                WHERE t.id = tab_id
                  AND g.created_by = auth.uid()
            )
        )
    );

-- Contact ownership cannot be transferred by updating an unclaimed row. The
-- claim flow below is the only path that changes a contact's claimed user.
DROP POLICY IF EXISTS "Users can update contacts they own or claim" ON public.contacts;
CREATE POLICY "Users can update contacts they own or claim"
    ON public.contacts FOR UPDATE
    TO authenticated
    USING (owner_user_id = auth.uid() OR claimed_user_id = auth.uid())
    WITH CHECK (owner_user_id = auth.uid() OR claimed_user_id = auth.uid());

-- Only the transaction creator may add its participant allocation rows.
DROP POLICY IF EXISTS "Transaction creator can insert participants" ON public.transaction_participants;
CREATE POLICY "Transaction creator can insert participants"
    ON public.transaction_participants FOR INSERT
    TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1
            FROM public.transactions t
            WHERE t.id = transaction_id
              AND t.created_by = auth.uid()
              AND public.is_tab_member(t.tab_id, auth.uid())
        )
    );

-- A participant may acknowledge their own allocation. Financial fields are
-- additionally protected by the tamper guard below.
DROP POLICY IF EXISTS "Participants or tab members can update participant status" ON public.transaction_participants;
CREATE POLICY "Participants or tab members can update participant status"
    ON public.transaction_participants FOR UPDATE
    TO authenticated
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

-- A debtor submits a pending payment for themselves. A counterpart may record
-- a payment as confirmed, but cannot use the same insert path to impersonate a
-- self-confirmed submission.
DROP POLICY IF EXISTS "Tab members can submit payments" ON public.payments;
CREATE POLICY "Tab members can submit payments"
    ON public.payments FOR INSERT
    TO authenticated
    WITH CHECK (
        public.is_tab_member(tab_id, auth.uid())
        AND (
            (
                submitted_by = auth.uid()
                AND confirmed_by IS NULL
                AND confirmed_at IS NULL
                AND status = 'submitted'
            )
            OR (
                confirmed_by = auth.uid()
                AND submitted_by <> auth.uid()
                AND confirmed_at IS NOT NULL
                AND status = 'confirmed'
            )
        )
    );

-- Payment status transitions must go through a future confirmation RPC, or the
-- existing safe insert path above. There is intentionally no direct UPDATE
-- policy for authenticated clients.
DROP POLICY IF EXISTS "Tab members can update payments" ON public.payments;

-- Notifications are generated by trusted server-side actions. Clients may read
-- and acknowledge their own notifications, but cannot inject arbitrary inbox
-- messages for other users.
DROP POLICY IF EXISTS "System and authenticated users can queue notifications" ON public.notifications;

-- ============================================================================
-- 2. APPEND-ONLY FINANCIAL FIELD GUARDS
-- ============================================================================

CREATE OR REPLACE FUNCTION public.prevent_tab_identity_tampering()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.tab_type IS DISTINCT FROM OLD.tab_type
       OR NEW.group_id IS DISTINCT FROM OLD.group_id
       OR NEW.user_a IS DISTINCT FROM OLD.user_a
       OR NEW.user_b IS DISTINCT FROM OLD.user_b THEN
        RAISE EXCEPTION 'Tab identity fields cannot be changed';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

DROP TRIGGER IF EXISTS trigger_prevent_tab_identity_tampering ON public.tabs;
CREATE TRIGGER trigger_prevent_tab_identity_tampering
    BEFORE UPDATE ON public.tabs
    FOR EACH ROW EXECUTE FUNCTION public.prevent_tab_identity_tampering();

CREATE OR REPLACE FUNCTION public.prevent_transaction_tampering()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.tab_id IS DISTINCT FROM OLD.tab_id
       OR NEW.created_by IS DISTINCT FROM OLD.created_by
       OR NEW.recurring_rule_id IS DISTINCT FROM OLD.recurring_rule_id
       OR NEW.transaction_type IS DISTINCT FROM OLD.transaction_type
       OR NEW.category IS DISTINCT FROM OLD.category
       OR NEW.description IS DISTINCT FROM OLD.description
       OR NEW.total_amount_centavos IS DISTINCT FROM OLD.total_amount_centavos
       OR NEW.currency IS DISTINCT FROM OLD.currency
       OR NEW.transaction_date IS DISTINCT FROM OLD.transaction_date
       OR NEW.due_date IS DISTINCT FROM OLD.due_date
       OR NEW.status IS DISTINCT FROM OLD.status THEN
        RAISE EXCEPTION 'Financial transaction fields cannot be changed';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

DROP TRIGGER IF EXISTS trigger_prevent_transaction_tampering ON public.transactions;
CREATE TRIGGER trigger_prevent_transaction_tampering
    BEFORE UPDATE ON public.transactions
    FOR EACH ROW EXECUTE FUNCTION public.prevent_transaction_tampering();

CREATE OR REPLACE FUNCTION public.prevent_participant_tampering()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.transaction_id IS DISTINCT FROM OLD.transaction_id
       OR NEW.contact_id IS DISTINCT FROM OLD.contact_id
       OR NEW.participant_role IS DISTINCT FROM OLD.participant_role
       OR NEW.share_amount_centavos IS DISTINCT FROM OLD.share_amount_centavos
       OR NEW.share_percentage IS DISTINCT FROM OLD.share_percentage THEN
        RAISE EXCEPTION 'Participant allocation fields cannot be changed';
    END IF;

    -- claim_contact() converts a virtual contact into the authenticated user.
    -- This is the one controlled exception to the user_id immutability rule.
    IF NEW.user_id IS DISTINCT FROM OLD.user_id
       AND NOT (
           OLD.user_id IS NULL
           AND OLD.contact_id IS NOT NULL
           AND NEW.user_id = auth.uid()
       ) THEN
        RAISE EXCEPTION 'Participant identity cannot be changed';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

DROP TRIGGER IF EXISTS trigger_prevent_participant_tampering ON public.transaction_participants;
CREATE TRIGGER trigger_prevent_participant_tampering
    BEFORE UPDATE ON public.transaction_participants
    FOR EACH ROW EXECUTE FUNCTION public.prevent_participant_tampering();

-- ============================================================================
-- 3. AUTHORIZED SECURITY-DEFINER FUNCTIONS
-- ============================================================================

-- Keep security-definer lookups independent of the caller's search_path.
ALTER FUNCTION public.is_tab_member(UUID, UUID) SET search_path = public, pg_temp;
ALTER FUNCTION public.is_group_member(UUID, UUID) SET search_path = public, pg_temp;
ALTER FUNCTION public.is_group_admin(UUID, UUID) SET search_path = public, pg_temp;
ALTER FUNCTION public.get_transaction_payer_id(UUID) SET search_path = public, pg_temp;
ALTER FUNCTION public.get_net_balance(UUID, UUID) SET search_path = public, pg_temp;
ALTER FUNCTION public.get_tab_summary(UUID, UUID) SET search_path = public, pg_temp;
ALTER FUNCTION public.get_user_dashboard_summary(UUID) SET search_path = public, pg_temp;
ALTER FUNCTION public.get_or_create_bilateral_tab(UUID, UUID) SET search_path = public, pg_temp;
ALTER FUNCTION public.claim_contact(UUID, UUID) SET search_path = public, pg_temp;
ALTER FUNCTION public.validate_transaction_split(UUID) SET search_path = public, pg_temp;
ALTER FUNCTION public.handle_new_user() SET search_path = public, pg_temp;
ALTER FUNCTION public.handle_updated_at() SET search_path = public, pg_temp;
ALTER FUNCTION public.log_transaction_activity() SET search_path = public, pg_temp;
ALTER FUNCTION public.log_payment_activity() SET search_path = public, pg_temp;
ALTER FUNCTION public.log_report_activity() SET search_path = public, pg_temp;

CREATE OR REPLACE FUNCTION public.search_users(p_query TEXT)
RETURNS TABLE (
    id UUID,
    display_name TEXT,
    avatar_url TEXT
) AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    IF length(trim(coalesce(p_query, ''))) < 2 THEN
        RETURN;
    END IF;

    RETURN QUERY
    SELECT u.id, u.display_name, u.avatar_url
    FROM public.users u
    WHERE u.display_name ILIKE '%' || trim(p_query) || '%'
       OR lower(u.email) = lower(trim(p_query))
    LIMIT 20;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public, pg_temp;

ALTER FUNCTION public.search_users(TEXT) SET search_path = public, pg_temp;

CREATE OR REPLACE FUNCTION public.get_net_balance(p_tab_id UUID, p_user_id UUID)
RETURNS BIGINT AS $$
DECLARE
    v_obligations_owed_to_user BIGINT := 0;
    v_obligations_owed_by_user BIGINT := 0;
    v_payments_received BIGINT := 0;
    v_payments_made BIGINT := 0;
BEGIN
    IF auth.uid() IS NULL
       OR p_user_id IS DISTINCT FROM auth.uid()
       OR NOT public.is_tab_member(p_tab_id, auth.uid()) THEN
        RAISE EXCEPTION 'Not authorized to view this tab balance';
    END IF;

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

    RETURN v_obligations_owed_to_user
        - v_obligations_owed_by_user
        - v_payments_received
        + v_payments_made;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public, pg_temp;

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
    IF auth.uid() IS NULL
       OR p_user_id IS DISTINCT FROM auth.uid()
       OR NOT public.is_tab_member(p_tab_id, auth.uid()) THEN
        RAISE EXCEPTION 'Not authorized to view this tab summary';
    END IF;

    SELECT tab_type, status INTO v_tab_type, v_tab_status
    FROM public.tabs
    WHERE id = p_tab_id;

    IF v_tab_type IS NULL THEN
        RETURN jsonb_build_object('error', 'Tab not found');
    END IF;

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

    v_net_balance := v_obligations_owed_to_user
        - v_obligations_owed_by_user
        - v_payments_received
        + v_payments_made;

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
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public, pg_temp;

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
    IF auth.uid() IS NULL OR p_user_id IS DISTINCT FROM auth.uid() THEN
        RAISE EXCEPTION 'Not authorized to view this dashboard';
    END IF;

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
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public, pg_temp;

CREATE OR REPLACE FUNCTION public.get_or_create_bilateral_tab(p_user_a UUID, p_user_b UUID)
RETURNS UUID AS $$
DECLARE
    v_tab_id UUID;
    v_first_user UUID;
    v_second_user UUID;
BEGIN
    IF auth.uid() IS NULL
       OR (p_user_a IS DISTINCT FROM auth.uid() AND p_user_b IS DISTINCT FROM auth.uid()) THEN
        RAISE EXCEPTION 'Only a tab participant can create or retrieve this tab';
    END IF;

    IF p_user_a IS NULL OR p_user_b IS NULL THEN
        RAISE EXCEPTION 'Both user IDs must be non-null';
    END IF;

    IF p_user_a = p_user_b THEN
        RAISE EXCEPTION 'Cannot create bilateral tab with oneself';
    END IF;

    IF p_user_a < p_user_b THEN
        v_first_user := p_user_a;
        v_second_user := p_user_b;
    ELSE
        v_first_user := p_user_b;
        v_second_user := p_user_a;
    END IF;

    SELECT id INTO v_tab_id
    FROM public.tabs
    WHERE tab_type = 'individual'
      AND status = 'active'
      AND user_a = v_first_user
      AND user_b = v_second_user
    LIMIT 1;

    IF v_tab_id IS NOT NULL THEN
        RETURN v_tab_id;
    END IF;

    BEGIN
        INSERT INTO public.tabs (tab_type, status, user_a, user_b)
        VALUES ('individual', 'active', v_first_user, v_second_user)
        RETURNING id INTO v_tab_id;

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
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

CREATE OR REPLACE FUNCTION public.claim_contact(p_contact_id UUID, p_claimed_user_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    v_contact RECORD;
BEGIN
    IF auth.uid() IS NULL OR p_claimed_user_id IS DISTINCT FROM auth.uid() THEN
        RAISE EXCEPTION 'Only the authenticated claimant can claim a contact';
    END IF;

    SELECT * INTO v_contact
    FROM public.contacts
    WHERE id = p_contact_id;

    IF v_contact.id IS NULL THEN
        RAISE EXCEPTION 'Contact not found';
    END IF;

    IF v_contact.claim_status = 'claimed' THEN
        RAISE EXCEPTION 'Contact has already been claimed';
    END IF;

    -- Require proof that the claimant matches the contact details recorded by
    -- the owner. This prevents claiming a leaked contact UUID as another user.
    IF NOT EXISTS (
        SELECT 1
        FROM auth.users au
        WHERE au.id = auth.uid()
          AND (
              (
                  v_contact.email IS NOT NULL
                  AND au.email IS NOT NULL
                  AND lower(trim(v_contact.email)) = lower(trim(au.email))
              )
              OR (
                  v_contact.phone IS NOT NULL
                  AND au.phone IS NOT NULL
                  AND regexp_replace(v_contact.phone, '[^0-9]', '', 'g')
                      = regexp_replace(au.phone, '[^0-9]', '', 'g')
              )
          )
    ) THEN
        RAISE EXCEPTION 'Authenticated account does not match this contact';
    END IF;

    UPDATE public.contacts
    SET claimed_user_id = p_claimed_user_id,
        claim_status = 'claimed',
        claimed_at = now()
    WHERE id = p_contact_id;

    UPDATE public.tab_members
    SET user_id = p_claimed_user_id
    WHERE contact_id = p_contact_id AND user_id IS NULL;

    UPDATE public.transaction_participants
    SET user_id = p_claimed_user_id
    WHERE contact_id = p_contact_id AND user_id IS NULL;

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
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

CREATE OR REPLACE FUNCTION public.validate_transaction_split(p_transaction_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    v_total BIGINT;
    v_sum_shares BIGINT;
    v_tab_id UUID;
BEGIN
    SELECT total_amount_centavos, tab_id
    INTO v_total, v_tab_id
    FROM public.transactions
    WHERE id = p_transaction_id;

    IF v_total IS NULL THEN
        RETURN FALSE;
    END IF;

    IF auth.uid() IS NULL OR NOT public.is_tab_member(v_tab_id, auth.uid()) THEN
        RAISE EXCEPTION 'Not authorized to validate this transaction';
    END IF;

    SELECT COALESCE(SUM(share_amount_centavos), 0)
    INTO v_sum_shares
    FROM public.transaction_participants
    WHERE transaction_id = p_transaction_id
      AND participant_role IN ('debtor', 'beneficiary');

    RETURN v_total = v_sum_shares;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public, pg_temp;

-- Explicit function grants: RPCs are authenticated-only, while trigger
-- functions and private helpers are not callable through PostgREST.
REVOKE EXECUTE ON FUNCTION public.is_tab_member(UUID, UUID) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.is_group_member(UUID, UUID) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.is_group_admin(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_tab_member(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_group_member(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_group_admin(UUID, UUID) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.get_transaction_payer_id(UUID) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.handle_updated_at() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.log_transaction_activity() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.log_payment_activity() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.log_report_activity() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.prevent_tab_identity_tampering() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.prevent_transaction_tampering() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.prevent_participant_tampering() FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE ON FUNCTION public.search_users(TEXT) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_net_balance(UUID, UUID) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_tab_summary(UUID, UUID) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_user_dashboard_summary(UUID) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_or_create_bilateral_tab(UUID, UUID) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.claim_contact(UUID, UUID) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.validate_transaction_split(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.search_users(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_net_balance(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_tab_summary(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_user_dashboard_summary(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_or_create_bilateral_tab(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.claim_contact(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.validate_transaction_split(UUID) TO authenticated;
