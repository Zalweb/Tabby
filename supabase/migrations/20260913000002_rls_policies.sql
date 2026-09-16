-- Tabby Database Migration: 20260913000002_rls_policies.sql
-- Description: Enables Row Level Security (RLS) and defines privacy policies for all 17 tables.
-- Specifications: AGENTS.md Section 7.4 (RLS Principles) & Section 9 (ADR-011).

-- ============================================================================
-- 0. SECURITY DEFINER HELPER FUNCTIONS
-- High-performance functions that bypass recursive RLS evaluations.
-- ============================================================================

-- Checks if a user is an active participant in a tab
CREATE OR REPLACE FUNCTION public.is_tab_member(p_tab_id UUID, p_user_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    IF p_user_id IS NULL OR p_tab_id IS NULL THEN
        RETURN FALSE;
    END IF;

    RETURN EXISTS (
        SELECT 1 FROM public.tab_members
        WHERE tab_id = p_tab_id AND user_id = p_user_id
    ) OR EXISTS (
        SELECT 1 FROM public.tabs
        WHERE id = p_tab_id AND (user_a = p_user_id OR user_b = p_user_id)
    ) OR EXISTS (
        SELECT 1 FROM public.tabs t
        JOIN public.group_members gm ON t.group_id = gm.group_id
        WHERE t.id = p_tab_id AND gm.user_id = p_user_id AND gm.status = 'active'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- Checks if a user is an active member of a group
CREATE OR REPLACE FUNCTION public.is_group_member(p_group_id UUID, p_user_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    IF p_user_id IS NULL OR p_group_id IS NULL THEN
        RETURN FALSE;
    END IF;

    RETURN EXISTS (
        SELECT 1 FROM public.group_members
        WHERE group_id = p_group_id AND user_id = p_user_id AND status = 'active'
    ) OR EXISTS (
        SELECT 1 FROM public.groups
        WHERE id = p_group_id AND created_by = p_user_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- Checks if a user is an admin of a group
CREATE OR REPLACE FUNCTION public.is_group_admin(p_group_id UUID, p_user_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    IF p_user_id IS NULL OR p_group_id IS NULL THEN
        RETURN FALSE;
    END IF;

    RETURN EXISTS (
        SELECT 1 FROM public.group_members
        WHERE group_id = p_group_id AND user_id = p_user_id AND role = 'admin' AND status = 'active'
    ) OR EXISTS (
        SELECT 1 FROM public.groups
        WHERE id = p_group_id AND created_by = p_user_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- ============================================================================
-- 1. USERS POLICIES
-- ============================================================================
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view all registered user profiles" ON public.users;
DROP POLICY IF EXISTS "Users can view their own profile and connected parties" ON public.users;
CREATE POLICY "Users can view their own profile and connected parties"
    ON public.users FOR SELECT
    TO authenticated
    USING (
        -- 1. Self: User can always view their own profile
        id = auth.uid()
        -- 2. Direct Bilateral Tab counterpart
        OR EXISTS (
            SELECT 1 FROM public.tabs t
            WHERE (t.user_a = auth.uid() AND t.user_b = public.users.id)
               OR (t.user_b = auth.uid() AND t.user_a = public.users.id)
        )
        -- 3. Multi-party Tab co-participant
        OR EXISTS (
            SELECT 1 FROM public.tab_members tm1
            JOIN public.tab_members tm2 ON tm1.tab_id = tm2.tab_id
            WHERE tm1.user_id = auth.uid() AND tm2.user_id = public.users.id
        )
        -- 4. Shared Group member
        OR EXISTS (
            SELECT 1 FROM public.group_members gm1
            JOIN public.group_members gm2 ON gm1.group_id = gm2.group_id
            WHERE gm1.user_id = auth.uid() AND gm2.user_id = public.users.id
              AND gm1.status = 'active' AND gm2.status = 'active'
        )
        -- 5. Friendships (requested or accepted)
        OR EXISTS (
            SELECT 1 FROM public.friendships f
            WHERE (f.requester_id = auth.uid() AND f.addressee_id = public.users.id)
               OR (f.addressee_id = auth.uid() AND f.requester_id = public.users.id)
        )
        -- 6. Virtual Contacts claimed
        OR EXISTS (
            SELECT 1 FROM public.contacts c
            WHERE c.owner_user_id = auth.uid() AND c.claimed_user_id = public.users.id
        )
    );

-- Sanitized user search function for friend discovery that exposes only public attributes
CREATE OR REPLACE FUNCTION public.search_users(p_query TEXT)
RETURNS TABLE (
    id UUID,
    display_name TEXT,
    avatar_url TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT u.id, u.display_name, u.avatar_url
    FROM public.users u
    WHERE u.display_name ILIKE '%' || p_query || '%'
       OR u.email ILIKE p_query
    LIMIT 20;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

GRANT EXECUTE ON FUNCTION public.search_users(TEXT) TO authenticated;

DROP POLICY IF EXISTS "Users can insert their own profile" ON public.users;
CREATE POLICY "Users can insert their own profile"
    ON public.users FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS "Users can update their own profile" ON public.users;
CREATE POLICY "Users can update their own profile"
    ON public.users FOR UPDATE
    TO authenticated
    USING (auth.uid() = id)
    WITH CHECK (auth.uid() = id);

-- ============================================================================
-- 2. CONTACTS POLICIES
-- ============================================================================
ALTER TABLE public.contacts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view contacts they own or where claimed" ON public.contacts;
CREATE POLICY "Users can view contacts they own or where claimed"
    ON public.contacts FOR SELECT
    TO authenticated
    USING (owner_user_id = auth.uid() OR claimed_user_id = auth.uid());

DROP POLICY IF EXISTS "Users can insert their own contacts" ON public.contacts;
CREATE POLICY "Users can insert their own contacts"
    ON public.contacts FOR INSERT
    TO authenticated
    WITH CHECK (owner_user_id = auth.uid());

DROP POLICY IF EXISTS "Users can update contacts they own or claim" ON public.contacts;
CREATE POLICY "Users can update contacts they own or claim"
    ON public.contacts FOR UPDATE
    TO authenticated
    USING (owner_user_id = auth.uid() OR claimed_user_id = auth.uid() OR claim_status = 'unclaimed')
    WITH CHECK (owner_user_id = auth.uid() OR claimed_user_id = auth.uid());

DROP POLICY IF EXISTS "Users can delete contacts they own" ON public.contacts;
CREATE POLICY "Users can delete contacts they own"
    ON public.contacts FOR DELETE
    TO authenticated
    USING (owner_user_id = auth.uid());

-- ============================================================================
-- 3. FRIENDSHIPS POLICIES
-- ============================================================================
ALTER TABLE public.friendships ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their friendships" ON public.friendships;
CREATE POLICY "Users can view their friendships"
    ON public.friendships FOR SELECT
    TO authenticated
    USING (requester_id = auth.uid() OR addressee_id = auth.uid());

DROP POLICY IF EXISTS "Users can request friendship" ON public.friendships;
CREATE POLICY "Users can request friendship"
    ON public.friendships FOR INSERT
    TO authenticated
    WITH CHECK (requester_id = auth.uid());

DROP POLICY IF EXISTS "Users can respond or modify their friendships" ON public.friendships;
CREATE POLICY "Users can respond or modify their friendships"
    ON public.friendships FOR UPDATE
    TO authenticated
    USING (requester_id = auth.uid() OR addressee_id = auth.uid());

DROP POLICY IF EXISTS "Users can delete their friendships" ON public.friendships;
CREATE POLICY "Users can delete their friendships"
    ON public.friendships FOR DELETE
    TO authenticated
    USING (requester_id = auth.uid() OR addressee_id = auth.uid());

-- ============================================================================
-- 4. GROUPS POLICIES
-- ============================================================================
ALTER TABLE public.groups ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Group members can view groups" ON public.groups;
CREATE POLICY "Group members can view groups"
    ON public.groups FOR SELECT
    TO authenticated
    USING (public.is_group_member(id, auth.uid()));

DROP POLICY IF EXISTS "Users can create groups" ON public.groups;
CREATE POLICY "Users can create groups"
    ON public.groups FOR INSERT
    TO authenticated
    WITH CHECK (created_by = auth.uid());

DROP POLICY IF EXISTS "Group admins can update groups" ON public.groups;
CREATE POLICY "Group admins can update groups"
    ON public.groups FOR UPDATE
    TO authenticated
    USING (public.is_group_admin(id, auth.uid()));

DROP POLICY IF EXISTS "Group creators can delete groups" ON public.groups;
CREATE POLICY "Group creators can delete groups"
    ON public.groups FOR DELETE
    TO authenticated
    USING (created_by = auth.uid());

-- ============================================================================
-- 5. GROUP_MEMBERS POLICIES
-- ============================================================================
ALTER TABLE public.group_members ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Members can view roster of their groups" ON public.group_members;
CREATE POLICY "Members can view roster of their groups"
    ON public.group_members FOR SELECT
    TO authenticated
    USING (public.is_group_member(group_id, auth.uid()) OR user_id = auth.uid());

DROP POLICY IF EXISTS "Group admins or creator can add members" ON public.group_members;
CREATE POLICY "Group admins or creator can add members"
    ON public.group_members FOR INSERT
    TO authenticated
    WITH CHECK (public.is_group_admin(group_id, auth.uid()) OR user_id = auth.uid());

DROP POLICY IF EXISTS "Group admins can update members or user can leave" ON public.group_members;
CREATE POLICY "Group admins can update members or user can leave"
    ON public.group_members FOR UPDATE
    TO authenticated
    USING (public.is_group_admin(group_id, auth.uid()) OR user_id = auth.uid());

DROP POLICY IF EXISTS "Group admins can remove members or user can leave" ON public.group_members;
CREATE POLICY "Group admins can remove members or user can leave"
    ON public.group_members FOR DELETE
    TO authenticated
    USING (public.is_group_admin(group_id, auth.uid()) OR user_id = auth.uid());

-- ============================================================================
-- 6. GROUP_PERMISSIONS POLICIES
-- ============================================================================
ALTER TABLE public.group_permissions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Group members can view permissions" ON public.group_permissions;
CREATE POLICY "Group members can view permissions"
    ON public.group_permissions FOR SELECT
    TO authenticated
    USING (public.is_group_member(group_id, auth.uid()));

DROP POLICY IF EXISTS "Group admins can manage permissions" ON public.group_permissions;
CREATE POLICY "Group admins can manage permissions"
    ON public.group_permissions FOR ALL
    TO authenticated
    USING (public.is_group_admin(group_id, auth.uid()))
    WITH CHECK (public.is_group_admin(group_id, auth.uid()));

-- ============================================================================
-- 7. TABS POLICIES
-- ============================================================================
ALTER TABLE public.tabs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Tab members can view their tabs" ON public.tabs;
CREATE POLICY "Tab members can view their tabs"
    ON public.tabs FOR SELECT
    TO authenticated
    USING (public.is_tab_member(id, auth.uid()));

DROP POLICY IF EXISTS "Authenticated users can create tabs" ON public.tabs;
CREATE POLICY "Authenticated users can create tabs"
    ON public.tabs FOR INSERT
    TO authenticated
    WITH CHECK (true);

DROP POLICY IF EXISTS "Tab members can update tabs" ON public.tabs;
CREATE POLICY "Tab members can update tabs"
    ON public.tabs FOR UPDATE
    TO authenticated
    USING (public.is_tab_member(id, auth.uid()));

-- ============================================================================
-- 8. TAB_MEMBERS POLICIES
-- ============================================================================
ALTER TABLE public.tab_members ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Tab members can view tab members" ON public.tab_members;
CREATE POLICY "Tab members can view tab members"
    ON public.tab_members FOR SELECT
    TO authenticated
    USING (public.is_tab_member(tab_id, auth.uid()) OR user_id = auth.uid());

DROP POLICY IF EXISTS "Tab members or creator can add tab members" ON public.tab_members;
CREATE POLICY "Tab members or creator can add tab members"
    ON public.tab_members FOR INSERT
    TO authenticated
    WITH CHECK (public.is_tab_member(tab_id, auth.uid()) OR user_id = auth.uid());

DROP POLICY IF EXISTS "Tab members can update tab membership" ON public.tab_members;
CREATE POLICY "Tab members can update tab membership"
    ON public.tab_members FOR UPDATE
    TO authenticated
    USING (public.is_tab_member(tab_id, auth.uid()));

DROP POLICY IF EXISTS "Tab members can remove members" ON public.tab_members;
CREATE POLICY "Tab members can remove members"
    ON public.tab_members FOR DELETE
    TO authenticated
    USING (public.is_tab_member(tab_id, auth.uid()));

-- ============================================================================
-- 9. RECURRING_RULES POLICIES
-- ============================================================================
ALTER TABLE public.recurring_rules ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Tab members can view recurring rules" ON public.recurring_rules;
CREATE POLICY "Tab members can view recurring rules"
    ON public.recurring_rules FOR SELECT
    TO authenticated
    USING (public.is_tab_member(tab_id, auth.uid()));

DROP POLICY IF EXISTS "Rule creators can insert recurring rules" ON public.recurring_rules;
CREATE POLICY "Rule creators can insert recurring rules"
    ON public.recurring_rules FOR INSERT
    TO authenticated
    WITH CHECK (created_by = auth.uid() AND public.is_tab_member(tab_id, auth.uid()));

DROP POLICY IF EXISTS "Rule creators can update recurring rules" ON public.recurring_rules;
CREATE POLICY "Rule creators can update recurring rules"
    ON public.recurring_rules FOR UPDATE
    TO authenticated
    USING (created_by = auth.uid());

DROP POLICY IF EXISTS "Rule creators can delete recurring rules" ON public.recurring_rules;
CREATE POLICY "Rule creators can delete recurring rules"
    ON public.recurring_rules FOR DELETE
    TO authenticated
    USING (created_by = auth.uid());

-- ============================================================================
-- 10. TRANSACTIONS POLICIES
-- Strictly restricted to members of the parent Tab (AGENTS.md Section 7.4).
-- ============================================================================
ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Tab members can view transactions" ON public.transactions;
CREATE POLICY "Tab members can view transactions"
    ON public.transactions FOR SELECT
    TO authenticated
    USING (public.is_tab_member(tab_id, auth.uid()));

DROP POLICY IF EXISTS "Tab members can insert transactions" ON public.transactions;
CREATE POLICY "Tab members can insert transactions"
    ON public.transactions FOR INSERT
    TO authenticated
    WITH CHECK (created_by = auth.uid() AND public.is_tab_member(tab_id, auth.uid()));

DROP POLICY IF EXISTS "Tab members can update transactions" ON public.transactions;
CREATE POLICY "Tab members can update transactions"
    ON public.transactions FOR UPDATE
    TO authenticated
    USING (public.is_tab_member(tab_id, auth.uid()));

DROP POLICY IF EXISTS "Transaction creators can soft delete transactions" ON public.transactions;
CREATE POLICY "Transaction creators can soft delete transactions"
    ON public.transactions FOR DELETE
    TO authenticated
    USING (created_by = auth.uid() AND public.is_tab_member(tab_id, auth.uid()));

-- ============================================================================
-- 11. TRANSACTION_PARTICIPANTS POLICIES
-- ============================================================================
ALTER TABLE public.transaction_participants ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Tab members can view transaction participants" ON public.transaction_participants;
CREATE POLICY "Tab members can view transaction participants"
    ON public.transaction_participants FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.transactions t
            WHERE t.id = transaction_id AND public.is_tab_member(t.tab_id, auth.uid())
        )
    );

DROP POLICY IF EXISTS "Transaction creator can insert participants" ON public.transaction_participants;
CREATE POLICY "Transaction creator can insert participants"
    ON public.transaction_participants FOR INSERT
    TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.transactions t
            WHERE t.id = transaction_id AND public.is_tab_member(t.tab_id, auth.uid())
        )
    );

DROP POLICY IF EXISTS "Participants or tab members can update participant status" ON public.transaction_participants;
CREATE POLICY "Participants or tab members can update participant status"
    ON public.transaction_participants FOR UPDATE
    TO authenticated
    USING (
        user_id = auth.uid() OR EXISTS (
            SELECT 1 FROM public.transactions t
            WHERE t.id = transaction_id AND public.is_tab_member(t.tab_id, auth.uid())
        )
    );

DROP POLICY IF EXISTS "Transaction creator can delete participant" ON public.transaction_participants;
CREATE POLICY "Transaction creator can delete participant"
    ON public.transaction_participants FOR DELETE
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.transactions t
            WHERE t.id = transaction_id AND t.created_by = auth.uid()
        )
    );

-- ============================================================================
-- 12. PAYMENTS POLICIES
-- ============================================================================
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Tab members can view payments" ON public.payments;
CREATE POLICY "Tab members can view payments"
    ON public.payments FOR SELECT
    TO authenticated
    USING (public.is_tab_member(tab_id, auth.uid()));

DROP POLICY IF EXISTS "Tab members can submit payments" ON public.payments;
CREATE POLICY "Tab members can submit payments"
    ON public.payments FOR INSERT
    TO authenticated
    WITH CHECK (
        public.is_tab_member(tab_id, auth.uid()) AND (
            submitted_by = auth.uid() OR
            confirmed_by = auth.uid()
        )
    );

DROP POLICY IF EXISTS "Tab members can update payments" ON public.payments;
CREATE POLICY "Tab members can update payments"
    ON public.payments FOR UPDATE
    TO authenticated
    USING (public.is_tab_member(tab_id, auth.uid()));

-- ============================================================================
-- 13. PAYMENT_PROOFS POLICIES
-- ============================================================================
ALTER TABLE public.payment_proofs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Tab members can view payment proofs" ON public.payment_proofs;
CREATE POLICY "Tab members can view payment proofs"
    ON public.payment_proofs FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.payments p
            WHERE p.id = payment_id AND public.is_tab_member(p.tab_id, auth.uid())
        )
    );

DROP POLICY IF EXISTS "Payment submitter can insert payment proofs" ON public.payment_proofs;
CREATE POLICY "Payment submitter can insert payment proofs"
    ON public.payment_proofs FOR INSERT
    TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.payments p
            WHERE p.id = payment_id AND p.submitted_by = auth.uid()
        )
    );

-- ============================================================================
-- 14. REMINDERS POLICIES
-- ============================================================================
ALTER TABLE public.reminders ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Sender and recipient can view reminders" ON public.reminders;
CREATE POLICY "Sender and recipient can view reminders"
    ON public.reminders FOR SELECT
    TO authenticated
    USING (created_by = auth.uid() OR recipient_user_id = auth.uid());

DROP POLICY IF EXISTS "Users can schedule reminders" ON public.reminders;
CREATE POLICY "Users can schedule reminders"
    ON public.reminders FOR INSERT
    TO authenticated
    WITH CHECK (created_by = auth.uid());

DROP POLICY IF EXISTS "Users can update their reminders" ON public.reminders;
CREATE POLICY "Users can update their reminders"
    ON public.reminders FOR UPDATE
    TO authenticated
    USING (created_by = auth.uid() OR recipient_user_id = auth.uid());

-- ============================================================================
-- 15. NOTIFICATIONS POLICIES
-- ============================================================================
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their notifications" ON public.notifications;
CREATE POLICY "Users can view their notifications"
    ON public.notifications FOR SELECT
    TO authenticated
    USING (recipient_user_id = auth.uid());

DROP POLICY IF EXISTS "System and authenticated users can queue notifications" ON public.notifications;
CREATE POLICY "System and authenticated users can queue notifications"
    ON public.notifications FOR INSERT
    TO authenticated
    WITH CHECK (true);

DROP POLICY IF EXISTS "Users can update their notification read status" ON public.notifications;
CREATE POLICY "Users can update their notification read status"
    ON public.notifications FOR UPDATE
    TO authenticated
    USING (recipient_user_id = auth.uid());

DROP POLICY IF EXISTS "Users can delete their notifications" ON public.notifications;
CREATE POLICY "Users can delete their notifications"
    ON public.notifications FOR DELETE
    TO authenticated
    USING (recipient_user_id = auth.uid());

-- ============================================================================
-- 16. REPORTS POLICIES
-- ============================================================================
ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view reports they filed" ON public.reports;
CREATE POLICY "Users can view reports they filed"
    ON public.reports FOR SELECT
    TO authenticated
    USING (reported_by = auth.uid());

DROP POLICY IF EXISTS "Users can file reports" ON public.reports;
CREATE POLICY "Users can file reports"
    ON public.reports FOR INSERT
    TO authenticated
    WITH CHECK (reported_by = auth.uid());

DROP POLICY IF EXISTS "Users can update reports they filed" ON public.reports;
CREATE POLICY "Users can update reports they filed"
    ON public.reports FOR UPDATE
    TO authenticated
    USING (reported_by = auth.uid());

-- ============================================================================
-- 17. ACTIVITY_LOGS POLICIES
-- Immutable append-only audit trail (AGENTS.md Section 7.4).
-- No UPDATE or DELETE policies are granted to prevent erasure of financial history.
-- ============================================================================
ALTER TABLE public.activity_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view activity logs for tabs they belong to" ON public.activity_logs;
CREATE POLICY "Users can view activity logs for tabs they belong to"
    ON public.activity_logs FOR SELECT
    TO authenticated
    USING (
        actor_user_id = auth.uid() OR
        (tab_id IS NOT NULL AND public.is_tab_member(tab_id, auth.uid())) OR
        (group_id IS NOT NULL AND public.is_group_member(group_id, auth.uid()))
    );

DROP POLICY IF EXISTS "Authenticated users can record activity logs" ON public.activity_logs;
CREATE POLICY "Authenticated users can record activity logs"
    ON public.activity_logs FOR INSERT
    TO authenticated
    WITH CHECK (actor_user_id = auth.uid());
