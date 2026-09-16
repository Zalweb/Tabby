-- ============================================================================
-- TABBY COMPLETE SUPABASE DATABASE SCHEMA (1-CLICK PROVISIONING)
-- ============================================================================
-- Application: Tabby ("Keep tabs. Settle up.")
-- Specification: AGENTS.md (Sections 7, 8; ADR-001, ADR-006, ADR-007, ADR-011)
-- Currency Standard: Philippine Peso integer centavos (BIGINT, 1 PHP = 100 centavos)
-- PostgreSQL Target: Supabase PostgreSQL 15+
--
-- Instructions:
-- Paste this entire file into the Supabase Dashboard SQL Editor and click "Run".
-- ============================================================================

-- ============================================================================
-- PART 1: EXTENSIONS & 17-ENTITY CORE SCHEMA
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 1. USERS TABLE
CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT UNIQUE,
    phone TEXT UNIQUE,
    display_name TEXT NOT NULL,
    avatar_url TEXT,
    gcash_number TEXT,
    maya_number TEXT,
    qr_code_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.users ADD COLUMN IF NOT EXISTS gcash_number TEXT;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS maya_number TEXT;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS qr_code_url TEXT;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'auth' AND table_name = 'users'
    ) AND NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_name = 'users_id_fkey_auth' AND table_name = 'users'
    ) THEN
        ALTER TABLE public.users
            ADD CONSTRAINT users_id_fkey_auth 
            FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;
    END IF;
END $$;

-- 2. CONTACTS TABLE
CREATE TABLE IF NOT EXISTS public.contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    display_name TEXT NOT NULL,
    phone TEXT,
    email TEXT,
    claimed_user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    claim_status TEXT NOT NULL DEFAULT 'unclaimed' CHECK (claim_status IN ('unclaimed', 'pending', 'claimed')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    claimed_at TIMESTAMPTZ
);

-- 3. FRIENDSHIPS TABLE
CREATE TABLE IF NOT EXISTS public.friendships (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    requester_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    addressee_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined', 'blocked')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    responded_at TIMESTAMPTZ,
    CONSTRAINT check_friendship_distinct_parties CHECK (requester_id <> addressee_id),
    CONSTRAINT unique_friendship_pair UNIQUE (requester_id, addressee_id)
);

-- 4. GROUPS TABLE
CREATE TABLE IF NOT EXISTS public.groups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_by UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    name TEXT NOT NULL,
    description TEXT,
    avatar_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 5. GROUP_MEMBERS TABLE
CREATE TABLE IF NOT EXISTS public.group_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id UUID NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    role TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('admin', 'member')),
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'invited', 'left')),
    joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT unique_group_member UNIQUE (group_id, user_id)
);

-- 6. GROUP_PERMISSIONS TABLE
CREATE TABLE IF NOT EXISTS public.group_permissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id UUID NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
    permission_key TEXT NOT NULL,
    enabled BOOLEAN NOT NULL DEFAULT true,
    CONSTRAINT unique_group_permission UNIQUE (group_id, permission_key)
);

-- 7. TABS TABLE
CREATE TABLE IF NOT EXISTS public.tabs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tab_type TEXT NOT NULL DEFAULT 'individual' CHECK (tab_type IN ('individual', 'group', 'shared_couple')),
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'settled', 'archived')),
    group_id UUID REFERENCES public.groups(id) ON DELETE SET NULL,
    user_a UUID REFERENCES public.users(id) ON DELETE SET NULL,
    user_b UUID REFERENCES public.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Canonical Bilateral Tab Unique Index (Section 7.3 Rule 2)
CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_bilateral_tab ON public.tabs (
    LEAST(user_a, user_b),
    GREATEST(user_a, user_b)
) WHERE tab_type = 'individual' AND status = 'active' AND user_a IS NOT NULL AND user_b IS NOT NULL;

-- 8. TAB_MEMBERS TABLE
CREATE TABLE IF NOT EXISTS public.tab_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tab_id UUID NOT NULL REFERENCES public.tabs(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    contact_id UUID REFERENCES public.contacts(id) ON DELETE CASCADE,
    role TEXT NOT NULL DEFAULT 'participant' CHECK (role IN ('participant', 'admin', 'viewer')),
    joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT check_tab_member_party CHECK (user_id IS NOT NULL OR contact_id IS NOT NULL)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_tab_members_unique_user ON public.tab_members (tab_id, user_id) WHERE user_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_tab_members_unique_contact ON public.tab_members (tab_id, contact_id) WHERE contact_id IS NOT NULL;

-- 9. RECURRING_RULES TABLE
CREATE TABLE IF NOT EXISTS public.recurring_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_by UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    tab_id UUID NOT NULL REFERENCES public.tabs(id) ON DELETE CASCADE,
    frequency TEXT NOT NULL CHECK (frequency IN ('daily', 'weekly', 'biweekly', 'monthly')),
    amount_centavos BIGINT NOT NULL CHECK (amount_centavos > 0),
    start_date DATE NOT NULL,
    end_date DATE,
    has_end_date BOOLEAN NOT NULL DEFAULT false,
    active BOOLEAN NOT NULL DEFAULT true,
    category TEXT NOT NULL DEFAULT 'other',
    description TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 10. TRANSACTIONS TABLE
CREATE TABLE IF NOT EXISTS public.transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tab_id UUID NOT NULL REFERENCES public.tabs(id) ON DELETE CASCADE,
    created_by UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    recurring_rule_id UUID REFERENCES public.recurring_rules(id) ON DELETE SET NULL,
    transaction_type TEXT NOT NULL DEFAULT 'shared_expense' CHECK (transaction_type IN ('debt', 'shared_expense', 'adjustment')),
    category TEXT NOT NULL DEFAULT 'other' CHECK (category IN ('food', 'transportation', 'borrowed_cash', 'bills', 'groceries', 'other')),
    description TEXT NOT NULL,
    total_amount_centavos BIGINT NOT NULL CHECK (total_amount_centavos > 0),
    currency TEXT NOT NULL DEFAULT 'PHP',
    transaction_date DATE NOT NULL DEFAULT CURRENT_DATE,
    due_date DATE,
    receipt_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS receipt_url TEXT;

-- 11. TRANSACTION_PARTICIPANTS TABLE
CREATE TABLE IF NOT EXISTS public.transaction_participants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_id UUID NOT NULL REFERENCES public.transactions(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    contact_id UUID REFERENCES public.contacts(id) ON DELETE CASCADE,
    participant_role TEXT NOT NULL DEFAULT 'debtor' CHECK (participant_role IN ('payer', 'debtor', 'beneficiary')),
    share_amount_centavos BIGINT NOT NULL DEFAULT 0 CHECK (share_amount_centavos >= 0),
    share_percentage NUMERIC(5,2),
    acknowledged BOOLEAN NOT NULL DEFAULT false,
    acknowledged_at TIMESTAMPTZ,
    CONSTRAINT check_participant_party CHECK (user_id IS NOT NULL OR contact_id IS NOT NULL)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_trans_part_unique_user ON public.transaction_participants (transaction_id, user_id) WHERE user_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_trans_part_unique_contact ON public.transaction_participants (transaction_id, contact_id) WHERE contact_id IS NOT NULL;

-- 12. PAYMENTS TABLE
CREATE TABLE IF NOT EXISTS public.payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tab_id UUID NOT NULL REFERENCES public.tabs(id) ON DELETE CASCADE,
    submitted_by UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    amount_centavos BIGINT NOT NULL CHECK (amount_centavos > 0),
    payment_method TEXT NOT NULL DEFAULT 'gcash' CHECK (payment_method IN ('gcash', 'maya', 'cash', 'bank_transfer', 'other')),
    note TEXT,
    status TEXT NOT NULL DEFAULT 'submitted' CHECK (status IN ('submitted', 'confirmed', 'rejected')),
    submitted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    confirmed_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
    confirmed_at TIMESTAMPTZ
);

-- 13. PAYMENT_PROOFS TABLE
CREATE TABLE IF NOT EXISTS public.payment_proofs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_id UUID NOT NULL REFERENCES public.payments(id) ON DELETE CASCADE,
    file_url TEXT NOT NULL,
    file_name TEXT NOT NULL,
    mime_type TEXT NOT NULL,
    uploaded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 14. REMINDERS TABLE
CREATE TABLE IF NOT EXISTS public.reminders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_id UUID NOT NULL REFERENCES public.transactions(id) ON DELETE CASCADE,
    created_by UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    recipient_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    reminder_type TEXT NOT NULL CHECK (reminder_type IN ('before_due', 'on_due', 'overdue', 'manual_nudge')),
    scheduled_for TIMESTAMPTZ NOT NULL,
    sent_at TIMESTAMPTZ,
    status TEXT NOT NULL DEFAULT 'scheduled' CHECK (status IN ('scheduled', 'sent', 'cancelled')),
    repeat_interval_minutes INTEGER
);

-- 15. NOTIFICATIONS TABLE
CREATE TABLE IF NOT EXISTS public.notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recipient_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    notification_type TEXT NOT NULL CHECK (notification_type IN (
        'debt_created', 'debt_acknowledged', 'amount_proposed', 'amount_changed',
        'payment_submitted', 'payment_confirmed', 'reminder_due', 'reminder_overdue',
        'manual_nudge', 'friend_request', 'group_invite', 'report_filed'
    )),
    related_tab_id UUID REFERENCES public.tabs(id) ON DELETE SET NULL,
    related_transaction_id UUID REFERENCES public.transactions(id) ON DELETE SET NULL,
    related_payment_id UUID REFERENCES public.payments(id) ON DELETE SET NULL,
    related_group_id UUID REFERENCES public.groups(id) ON DELETE SET NULL,
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    is_read BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    read_at TIMESTAMPTZ
);

-- 16. REPORTS TABLE
CREATE TABLE IF NOT EXISTS public.reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reported_by UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    tab_id UUID REFERENCES public.tabs(id) ON DELETE SET NULL,
    transaction_id UUID REFERENCES public.transactions(id) ON DELETE SET NULL,
    payment_id UUID REFERENCES public.payments(id) ON DELETE SET NULL,
    report_type TEXT NOT NULL CHECK (report_type IN ('amount_dispute', 'unrecognized_debt', 'payment_dispute', 'other')),
    message TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'under_review', 'resolved', 'dismissed')),
    resolution_note TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    resolved_at TIMESTAMPTZ
);

-- 17. ACTIVITY_LOGS TABLE
CREATE TABLE IF NOT EXISTS public.activity_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    tab_id UUID REFERENCES public.tabs(id) ON DELETE SET NULL,
    transaction_id UUID REFERENCES public.transactions(id) ON DELETE SET NULL,
    payment_id UUID REFERENCES public.payments(id) ON DELETE SET NULL,
    group_id UUID REFERENCES public.groups(id) ON DELETE SET NULL,
    event_type TEXT NOT NULL,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- PERFORMANCE INDEXES
CREATE INDEX IF NOT EXISTS idx_contacts_owner ON public.contacts(owner_user_id);
CREATE INDEX IF NOT EXISTS idx_contacts_claimed ON public.contacts(claimed_user_id);
CREATE INDEX IF NOT EXISTS idx_contacts_phone ON public.contacts(phone);
CREATE INDEX IF NOT EXISTS idx_contacts_email ON public.contacts(email);

CREATE INDEX IF NOT EXISTS idx_friendships_requester ON public.friendships(requester_id);
CREATE INDEX IF NOT EXISTS idx_friendships_addressee ON public.friendships(addressee_id);
CREATE INDEX IF NOT EXISTS idx_friendships_status ON public.friendships(status);

CREATE INDEX IF NOT EXISTS idx_groups_created_by ON public.groups(created_by);
CREATE INDEX IF NOT EXISTS idx_group_members_group ON public.group_members(group_id);
CREATE INDEX IF NOT EXISTS idx_group_members_user ON public.group_members(user_id);
CREATE INDEX IF NOT EXISTS idx_group_permissions_group ON public.group_permissions(group_id);

CREATE INDEX IF NOT EXISTS idx_tabs_group ON public.tabs(group_id);
CREATE INDEX IF NOT EXISTS idx_tabs_status ON public.tabs(status);
CREATE INDEX IF NOT EXISTS idx_tabs_user_a ON public.tabs(user_a);
CREATE INDEX IF NOT EXISTS idx_tabs_user_b ON public.tabs(user_b);
CREATE INDEX IF NOT EXISTS idx_tab_members_tab ON public.tab_members(tab_id);
CREATE INDEX IF NOT EXISTS idx_tab_members_user ON public.tab_members(user_id);
CREATE INDEX IF NOT EXISTS idx_tab_members_contact ON public.tab_members(contact_id);

CREATE INDEX IF NOT EXISTS idx_recurring_rules_tab ON public.recurring_rules(tab_id);
CREATE INDEX IF NOT EXISTS idx_recurring_rules_created_by ON public.recurring_rules(created_by);
CREATE INDEX IF NOT EXISTS idx_recurring_rules_active ON public.recurring_rules(active);

CREATE INDEX IF NOT EXISTS idx_transactions_tab ON public.transactions(tab_id);
CREATE INDEX IF NOT EXISTS idx_transactions_created_by ON public.transactions(created_by);
CREATE INDEX IF NOT EXISTS idx_transactions_date ON public.transactions(transaction_date);
CREATE INDEX IF NOT EXISTS idx_transactions_status ON public.transactions(status);
CREATE INDEX IF NOT EXISTS idx_transactions_recurring_rule ON public.transactions(recurring_rule_id);
CREATE INDEX IF NOT EXISTS idx_trans_participants_tx ON public.transaction_participants(transaction_id);
CREATE INDEX IF NOT EXISTS idx_trans_participants_user ON public.transaction_participants(user_id);
CREATE INDEX IF NOT EXISTS idx_trans_participants_contact ON public.transaction_participants(contact_id);

CREATE INDEX IF NOT EXISTS idx_payments_tab ON public.payments(tab_id);
CREATE INDEX IF NOT EXISTS idx_payments_submitted_by ON public.payments(submitted_by);
CREATE INDEX IF NOT EXISTS idx_payments_confirmed_by ON public.payments(confirmed_by);
CREATE INDEX IF NOT EXISTS idx_payments_status ON public.payments(status);
CREATE INDEX IF NOT EXISTS idx_payment_proofs_payment ON public.payment_proofs(payment_id);

CREATE INDEX IF NOT EXISTS idx_reminders_tx ON public.reminders(transaction_id);
CREATE INDEX IF NOT EXISTS idx_reminders_recipient ON public.reminders(recipient_user_id);
CREATE INDEX IF NOT EXISTS idx_reminders_status ON public.reminders(status);
CREATE INDEX IF NOT EXISTS idx_reminders_scheduled ON public.reminders(scheduled_for);
CREATE INDEX IF NOT EXISTS idx_notifications_recipient ON public.notifications(recipient_user_id, is_read);
CREATE INDEX IF NOT EXISTS idx_notifications_created ON public.notifications(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_reports_reported_by ON public.reports(reported_by);
CREATE INDEX IF NOT EXISTS idx_reports_tab ON public.reports(tab_id);
CREATE INDEX IF NOT EXISTS idx_reports_status ON public.reports(status);
CREATE INDEX IF NOT EXISTS idx_activity_logs_tab ON public.activity_logs(tab_id);
CREATE INDEX IF NOT EXISTS idx_activity_logs_actor ON public.activity_logs(actor_user_id);
CREATE INDEX IF NOT EXISTS idx_activity_logs_tx ON public.activity_logs(transaction_id);
CREATE INDEX IF NOT EXISTS idx_activity_logs_payment ON public.activity_logs(payment_id);
CREATE INDEX IF NOT EXISTS idx_activity_logs_created ON public.activity_logs(created_at DESC);

-- Supabase Auth Auto-Provisioning
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.users (id, email, phone, display_name, avatar_url)
    VALUES (
        NEW.id,
        NEW.email,
        NEW.phone,
        COALESCE(
            NEW.raw_user_meta_data->>'display_name',
            NEW.raw_user_meta_data->>'name',
            split_part(COALESCE(NEW.email, 'User'), '@', 1)
        ),
        NEW.raw_user_meta_data->>'avatar_url'
    )
    ON CONFLICT (id) DO UPDATE SET
        email = EXCLUDED.email,
        phone = EXCLUDED.phone,
        updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'auth' AND table_name = 'users'
    ) THEN
        DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
        CREATE TRIGGER on_auth_user_created
            AFTER INSERT OR UPDATE OF email, phone, raw_user_meta_data ON auth.users
            FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
    END IF;
END $$;

-- ============================================================================
-- PART 2: ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================================================

-- Security Definer Helpers
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

-- RLS: USERS
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view all registered user profiles" ON public.users;
DROP POLICY IF EXISTS "Users can view their own profile and connected parties" ON public.users;
CREATE POLICY "Users can view their own profile and connected parties"
    ON public.users FOR SELECT
    TO authenticated
    USING (
        -- 1. Self
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
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

GRANT EXECUTE ON FUNCTION public.search_users(TEXT) TO authenticated;
DROP POLICY IF EXISTS "Users can insert their own profile" ON public.users;
CREATE POLICY "Users can insert their own profile"
    ON public.users FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);
DROP POLICY IF EXISTS "Users can update their own profile" ON public.users;
CREATE POLICY "Users can update their own profile"
    ON public.users FOR UPDATE TO authenticated USING (auth.uid() = id) WITH CHECK (auth.uid() = id);

-- RLS: CONTACTS
ALTER TABLE public.contacts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view contacts they own or where claimed" ON public.contacts;
CREATE POLICY "Users can view contacts they own or where claimed"
    ON public.contacts FOR SELECT TO authenticated USING (owner_user_id = auth.uid() OR claimed_user_id = auth.uid());
DROP POLICY IF EXISTS "Users can insert their own contacts" ON public.contacts;
CREATE POLICY "Users can insert their own contacts"
    ON public.contacts FOR INSERT TO authenticated WITH CHECK (owner_user_id = auth.uid());
DROP POLICY IF EXISTS "Users can update contacts they own or claim" ON public.contacts;
CREATE POLICY "Users can update contacts they own or claim"
    ON public.contacts FOR UPDATE TO authenticated
    USING (owner_user_id = auth.uid() OR claimed_user_id = auth.uid())
    WITH CHECK (owner_user_id = auth.uid() OR claimed_user_id = auth.uid());
DROP POLICY IF EXISTS "Users can delete contacts they own" ON public.contacts;
CREATE POLICY "Users can delete contacts they own"
    ON public.contacts FOR DELETE TO authenticated USING (owner_user_id = auth.uid());

-- RLS: FRIENDSHIPS
ALTER TABLE public.friendships ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view their friendships" ON public.friendships;
CREATE POLICY "Users can view their friendships"
    ON public.friendships FOR SELECT TO authenticated USING (requester_id = auth.uid() OR addressee_id = auth.uid());
DROP POLICY IF EXISTS "Users can request friendship" ON public.friendships;
CREATE POLICY "Users can request friendship"
    ON public.friendships FOR INSERT TO authenticated WITH CHECK (requester_id = auth.uid());
DROP POLICY IF EXISTS "Users can respond or modify their friendships" ON public.friendships;
CREATE POLICY "Users can respond or modify their friendships"
    ON public.friendships FOR UPDATE TO authenticated USING (requester_id = auth.uid() OR addressee_id = auth.uid());
DROP POLICY IF EXISTS "Users can delete their friendships" ON public.friendships;
CREATE POLICY "Users can delete their friendships"
    ON public.friendships FOR DELETE TO authenticated USING (requester_id = auth.uid() OR addressee_id = auth.uid());

-- RLS: GROUPS
ALTER TABLE public.groups ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Group members can view groups" ON public.groups;
CREATE POLICY "Group members can view groups"
    ON public.groups FOR SELECT TO authenticated USING (public.is_group_member(id, auth.uid()));
DROP POLICY IF EXISTS "Users can create groups" ON public.groups;
CREATE POLICY "Users can create groups"
    ON public.groups FOR INSERT TO authenticated WITH CHECK (created_by = auth.uid());
DROP POLICY IF EXISTS "Group admins can update groups" ON public.groups;
CREATE POLICY "Group admins can update groups"
    ON public.groups FOR UPDATE TO authenticated USING (public.is_group_admin(id, auth.uid()));
DROP POLICY IF EXISTS "Group creators can delete groups" ON public.groups;
CREATE POLICY "Group creators can delete groups"
    ON public.groups FOR DELETE TO authenticated USING (created_by = auth.uid());

-- RLS: GROUP_MEMBERS
ALTER TABLE public.group_members ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Members can view roster of their groups" ON public.group_members;
CREATE POLICY "Members can view roster of their groups"
    ON public.group_members FOR SELECT TO authenticated USING (public.is_group_member(group_id, auth.uid()) OR user_id = auth.uid());
DROP POLICY IF EXISTS "Group admins or creator can add members" ON public.group_members;
CREATE POLICY "Group admins or creator can add members"
    ON public.group_members FOR INSERT TO authenticated WITH CHECK (
        public.is_group_admin(group_id, auth.uid())
        OR (
            user_id = auth.uid()
            AND EXISTS (
                SELECT 1 FROM public.groups g
                WHERE g.id = group_id AND g.created_by = auth.uid()
            )
        )
    );
DROP POLICY IF EXISTS "Group admins can update members or user can leave" ON public.group_members;
CREATE POLICY "Group admins can update members or user can leave"
    ON public.group_members FOR UPDATE TO authenticated USING (public.is_group_admin(group_id, auth.uid()) OR user_id = auth.uid());
DROP POLICY IF EXISTS "Group admins can remove members or user can leave" ON public.group_members;
CREATE POLICY "Group admins can remove members or user can leave"
    ON public.group_members FOR DELETE TO authenticated USING (public.is_group_admin(group_id, auth.uid()) OR user_id = auth.uid());

-- RLS: GROUP_PERMISSIONS
ALTER TABLE public.group_permissions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Group members can view permissions" ON public.group_permissions;
CREATE POLICY "Group members can view permissions"
    ON public.group_permissions FOR SELECT TO authenticated USING (public.is_group_member(group_id, auth.uid()));
DROP POLICY IF EXISTS "Group admins can manage permissions" ON public.group_permissions;
CREATE POLICY "Group admins can manage permissions"
    ON public.group_permissions FOR ALL TO authenticated USING (public.is_group_admin(group_id, auth.uid())) WITH CHECK (public.is_group_admin(group_id, auth.uid()));

-- RLS: TABS
ALTER TABLE public.tabs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Tab members can view their tabs" ON public.tabs;
CREATE POLICY "Tab members can view their tabs"
    ON public.tabs FOR SELECT TO authenticated USING (public.is_tab_member(id, auth.uid()));
DROP POLICY IF EXISTS "Authenticated users can create tabs" ON public.tabs;
CREATE POLICY "Authenticated users can create tabs"
    ON public.tabs FOR INSERT TO authenticated WITH CHECK (
        (
            tab_type IN ('individual', 'shared_couple')
            AND user_a IS NOT NULL AND user_b IS NOT NULL
            AND user_a <> user_b
            AND (user_a = auth.uid() OR user_b = auth.uid())
        )
        OR (
            tab_type = 'group' AND group_id IS NOT NULL
            AND EXISTS (
                SELECT 1 FROM public.groups g
                WHERE g.id = group_id AND g.created_by = auth.uid()
            )
        )
    );
DROP POLICY IF EXISTS "Tab members can update tabs" ON public.tabs;
CREATE POLICY "Tab members can update tabs"
    ON public.tabs FOR UPDATE TO authenticated USING (public.is_tab_member(id, auth.uid()));

-- RLS: TAB_MEMBERS
ALTER TABLE public.tab_members ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Tab members can view tab members" ON public.tab_members;
CREATE POLICY "Tab members can view tab members"
    ON public.tab_members FOR SELECT TO authenticated USING (public.is_tab_member(tab_id, auth.uid()) OR user_id = auth.uid());
DROP POLICY IF EXISTS "Tab members or creator can add tab members" ON public.tab_members;
CREATE POLICY "Tab members or creator can add tab members"
    ON public.tab_members FOR INSERT TO authenticated WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.tab_members tm
            WHERE tm.tab_id = tab_id
              AND tm.user_id = auth.uid()
              AND tm.role = 'admin'
        )
        OR (
            user_id = auth.uid()
            AND EXISTS (
                SELECT 1
                FROM public.tabs t
                JOIN public.groups g ON g.id = t.group_id
                WHERE t.id = tab_id AND g.created_by = auth.uid()
            )
        )
    );
DROP POLICY IF EXISTS "Tab members can update tab membership" ON public.tab_members;
CREATE POLICY "Tab members can update tab membership"
    ON public.tab_members FOR UPDATE TO authenticated USING (public.is_tab_member(tab_id, auth.uid()));
DROP POLICY IF EXISTS "Tab members can remove members" ON public.tab_members;
CREATE POLICY "Tab members can remove members"
    ON public.tab_members FOR DELETE TO authenticated USING (public.is_tab_member(tab_id, auth.uid()));

-- RLS: RECURRING_RULES
ALTER TABLE public.recurring_rules ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Tab members can view recurring rules" ON public.recurring_rules;
CREATE POLICY "Tab members can view recurring rules"
    ON public.recurring_rules FOR SELECT TO authenticated USING (public.is_tab_member(tab_id, auth.uid()));
DROP POLICY IF EXISTS "Rule creators can insert recurring rules" ON public.recurring_rules;
CREATE POLICY "Rule creators can insert recurring rules"
    ON public.recurring_rules FOR INSERT TO authenticated WITH CHECK (created_by = auth.uid() AND public.is_tab_member(tab_id, auth.uid()));
DROP POLICY IF EXISTS "Rule creators can update recurring rules" ON public.recurring_rules;
CREATE POLICY "Rule creators can update recurring rules"
    ON public.recurring_rules FOR UPDATE TO authenticated USING (created_by = auth.uid());
DROP POLICY IF EXISTS "Rule creators can delete recurring rules" ON public.recurring_rules;
CREATE POLICY "Rule creators can delete recurring rules"
    ON public.recurring_rules FOR DELETE TO authenticated USING (created_by = auth.uid());

-- RLS: TRANSACTIONS
ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Tab members can view transactions" ON public.transactions;
CREATE POLICY "Tab members can view transactions"
    ON public.transactions FOR SELECT TO authenticated USING (public.is_tab_member(tab_id, auth.uid()));
DROP POLICY IF EXISTS "Tab members can insert transactions" ON public.transactions;
CREATE POLICY "Tab members can insert transactions"
    ON public.transactions FOR INSERT TO authenticated WITH CHECK (created_by = auth.uid() AND public.is_tab_member(tab_id, auth.uid()));
DROP POLICY IF EXISTS "Tab members can update transactions" ON public.transactions;
CREATE POLICY "Tab members can update transactions"
    ON public.transactions FOR UPDATE TO authenticated USING (public.is_tab_member(tab_id, auth.uid()));
DROP POLICY IF EXISTS "Transaction creators can soft delete transactions" ON public.transactions;
CREATE POLICY "Transaction creators can soft delete transactions"
    ON public.transactions FOR DELETE TO authenticated USING (created_by = auth.uid() AND public.is_tab_member(tab_id, auth.uid()));

-- RLS: TRANSACTION_PARTICIPANTS
ALTER TABLE public.transaction_participants ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Tab members can view transaction participants" ON public.transaction_participants;
CREATE POLICY "Tab members can view transaction participants"
    ON public.transaction_participants FOR SELECT TO authenticated USING (
        EXISTS (
            SELECT 1 FROM public.transactions t
            WHERE t.id = transaction_id AND public.is_tab_member(t.tab_id, auth.uid())
        )
    );
DROP POLICY IF EXISTS "Transaction creator can insert participants" ON public.transaction_participants;
CREATE POLICY "Transaction creator can insert participants"
    ON public.transaction_participants FOR INSERT TO authenticated WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.transactions t
            WHERE t.id = transaction_id
              AND t.created_by = auth.uid()
              AND public.is_tab_member(t.tab_id, auth.uid())
        )
    );
DROP POLICY IF EXISTS "Participants or tab members can update participant status" ON public.transaction_participants;
CREATE POLICY "Participants or tab members can update participant status"
    ON public.transaction_participants FOR UPDATE TO authenticated
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());
DROP POLICY IF EXISTS "Transaction creator can delete participant" ON public.transaction_participants;
CREATE POLICY "Transaction creator can delete participant"
    ON public.transaction_participants FOR DELETE TO authenticated USING (
        EXISTS (
            SELECT 1 FROM public.transactions t
            WHERE t.id = transaction_id AND t.created_by = auth.uid()
        )
    );

-- RLS: PAYMENTS
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Tab members can view payments" ON public.payments;
CREATE POLICY "Tab members can view payments"
    ON public.payments FOR SELECT TO authenticated USING (public.is_tab_member(tab_id, auth.uid()));
DROP POLICY IF EXISTS "Tab members can submit payments" ON public.payments;
CREATE POLICY "Tab members can submit payments"
    ON public.payments FOR INSERT TO authenticated WITH CHECK (
        public.is_tab_member(tab_id, auth.uid()) AND (
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
DROP POLICY IF EXISTS "Tab members can update payments" ON public.payments;

-- RLS: PAYMENT_PROOFS
ALTER TABLE public.payment_proofs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Tab members can view payment proofs" ON public.payment_proofs;
CREATE POLICY "Tab members can view payment proofs"
    ON public.payment_proofs FOR SELECT TO authenticated USING (
        EXISTS (
            SELECT 1 FROM public.payments p
            WHERE p.id = payment_id AND public.is_tab_member(p.tab_id, auth.uid())
        )
    );
DROP POLICY IF EXISTS "Payment submitter can insert payment proofs" ON public.payment_proofs;
CREATE POLICY "Payment submitter can insert payment proofs"
    ON public.payment_proofs FOR INSERT TO authenticated WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.payments p
            WHERE p.id = payment_id AND p.submitted_by = auth.uid()
        )
    );

-- RLS: REMINDERS
ALTER TABLE public.reminders ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Sender and recipient can view reminders" ON public.reminders;
CREATE POLICY "Sender and recipient can view reminders"
    ON public.reminders FOR SELECT TO authenticated USING (created_by = auth.uid() OR recipient_user_id = auth.uid());
DROP POLICY IF EXISTS "Users can schedule reminders" ON public.reminders;
CREATE POLICY "Users can schedule reminders"
    ON public.reminders FOR INSERT TO authenticated WITH CHECK (created_by = auth.uid());
DROP POLICY IF EXISTS "Users can update their reminders" ON public.reminders;
CREATE POLICY "Users can update their reminders"
    ON public.reminders FOR UPDATE TO authenticated USING (created_by = auth.uid() OR recipient_user_id = auth.uid());
DROP POLICY IF EXISTS "Users can delete their reminders" ON public.reminders;
CREATE POLICY "Users can delete their reminders"
    ON public.reminders FOR DELETE TO authenticated USING (created_by = auth.uid());

-- RLS: NOTIFICATIONS
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view their notifications" ON public.notifications;
CREATE POLICY "Users can view their notifications"
    ON public.notifications FOR SELECT TO authenticated USING (recipient_user_id = auth.uid());
DROP POLICY IF EXISTS "System and authenticated users can queue notifications" ON public.notifications;
DROP POLICY IF EXISTS "Users can update their notification read status" ON public.notifications;
CREATE POLICY "Users can update their notification read status"
    ON public.notifications FOR UPDATE TO authenticated USING (recipient_user_id = auth.uid());
DROP POLICY IF EXISTS "Users can delete their notifications" ON public.notifications;
CREATE POLICY "Users can delete their notifications"
    ON public.notifications FOR DELETE TO authenticated USING (recipient_user_id = auth.uid());

-- RLS: REPORTS
ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view reports they filed" ON public.reports;
CREATE POLICY "Users can view reports they filed"
    ON public.reports FOR SELECT TO authenticated USING (reported_by = auth.uid());
DROP POLICY IF EXISTS "Users can file reports" ON public.reports;
CREATE POLICY "Users can file reports"
    ON public.reports FOR INSERT TO authenticated WITH CHECK (reported_by = auth.uid());
DROP POLICY IF EXISTS "Users can update reports they filed" ON public.reports;
CREATE POLICY "Users can update reports they filed"
    ON public.reports FOR UPDATE TO authenticated USING (reported_by = auth.uid());

-- RLS: ACTIVITY_LOGS (Append-Only)
ALTER TABLE public.activity_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view activity logs for tabs they belong to" ON public.activity_logs;
CREATE POLICY "Users can view activity logs for tabs they belong to"
    ON public.activity_logs FOR SELECT TO authenticated USING (
        actor_user_id = auth.uid() OR
        (tab_id IS NOT NULL AND public.is_tab_member(tab_id, auth.uid())) OR
        (group_id IS NOT NULL AND public.is_group_member(group_id, auth.uid()))
    );
DROP POLICY IF EXISTS "Authenticated users can record activity logs" ON public.activity_logs;
CREATE POLICY "Authenticated users can record activity logs"
    ON public.activity_logs FOR INSERT TO authenticated WITH CHECK (actor_user_id = auth.uid());

-- ============================================================================
-- PART 3: BALANCE CALCULATION ENGINE FUNCTIONS & RPCS
-- ============================================================================

-- Helper: Get Transaction Payer ID
CREATE OR REPLACE FUNCTION public.get_transaction_payer_id(p_transaction_id UUID)
RETURNS UUID AS $$
DECLARE
    v_payer_id UUID;
BEGIN
    SELECT user_id INTO v_payer_id
    FROM public.transaction_participants
    WHERE transaction_id = p_transaction_id AND participant_role = 'payer' AND user_id IS NOT NULL
    LIMIT 1;

    IF v_payer_id IS NULL THEN
        SELECT created_by INTO v_payer_id
        FROM public.transactions
        WHERE id = p_transaction_id;
    END IF;

    RETURN v_payer_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- Core RPC: get_net_balance
CREATE OR REPLACE FUNCTION public.get_net_balance(p_tab_id UUID, p_user_id UUID)
RETURNS BIGINT AS $$
DECLARE
    v_obligations_owed_to_user BIGINT := 0;
    v_obligations_owed_by_user BIGINT := 0;
    v_payments_received BIGINT := 0;
    v_payments_made BIGINT := 0;
    v_net_balance BIGINT := 0;
BEGIN
    IF auth.uid() IS NULL
       OR p_user_id IS DISTINCT FROM auth.uid()
       OR NOT public.is_tab_member(p_tab_id, auth.uid()) THEN
        RAISE EXCEPTION 'Not authorized to view this tab balance';
    END IF;

    -- 1. Obligations Owed TO User A:
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
    SELECT COALESCE(SUM(p.amount_centavos), 0)
    INTO v_payments_made
    FROM public.payments p
    WHERE p.tab_id = p_tab_id
      AND p.status = 'confirmed'
      AND p.submitted_by = p_user_id;

    v_net_balance := v_obligations_owed_to_user - v_obligations_owed_by_user - v_payments_received + v_payments_made;

    RETURN v_net_balance;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- RPC: get_tab_summary
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

    v_net_balance := v_obligations_owed_to_user - v_obligations_owed_by_user - v_payments_received + v_payments_made;

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

-- RPC: get_user_dashboard_summary
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
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- RPC: get_or_create_bilateral_tab
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

-- RPC: claim_contact (ADR-007)
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
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- PART 4: STORAGE BUCKETS & AUTOMATED TRIGGERS
-- ============================================================================

-- Storage Bucket ('payment-proofs')
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'storage' AND table_name = 'buckets'
    ) THEN
        INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
        VALUES (
            'payment-proofs',
            'payment-proofs',
            false,
            10485760, -- 10 MB per receipt screenshot
            ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/jpg']
        )
        ON CONFLICT (id) DO UPDATE SET
            public = false,
            file_size_limit = 10485760,
            allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/jpg'];
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'storage' AND table_name = 'objects'
    ) THEN
        DROP POLICY IF EXISTS "Authenticated users can upload payment proofs" ON storage.objects;
        CREATE POLICY "Authenticated users can upload payment proofs"
            ON storage.objects FOR INSERT TO authenticated
            WITH CHECK (
                bucket_id = 'payment-proofs' 
                AND (
                    (storage.foldername(name))[1] = auth.uid()::text
                    OR name LIKE auth.uid()::text || '/%'
                    OR (storage.foldername(name))[1] = 'receipts'
                )
            );

        DROP POLICY IF EXISTS "Authenticated users can view payment proofs" ON storage.objects;
        CREATE POLICY "Authenticated users can view payment proofs"
            ON storage.objects FOR SELECT TO authenticated
            USING (
                bucket_id = 'payment-proofs'
                AND (
                    (storage.foldername(name))[1] = auth.uid()::text
                    OR name LIKE auth.uid()::text || '/%'
                    OR EXISTS (
                        SELECT 1 FROM public.payment_proofs pp
                        JOIN public.payments p ON pp.payment_id = p.id
                        WHERE (pp.file_url = name OR pp.file_name = name OR pp.file_url LIKE '%' || name)
                          AND public.is_tab_member(p.tab_id, auth.uid())
                    )
                    OR EXISTS (
                        SELECT 1 FROM public.transactions tx
                        WHERE (tx.receipt_url = name OR tx.receipt_url LIKE '%' || name)
                          AND public.is_tab_member(tx.tab_id, auth.uid())
                    )
                )
            );

        DROP POLICY IF EXISTS "Users can delete their own payment proofs" ON storage.objects;
        CREATE POLICY "Users can delete their own payment proofs"
            ON storage.objects FOR DELETE TO authenticated
            USING (
                bucket_id = 'payment-proofs' 
                AND (
                    (storage.foldername(name))[1] = auth.uid()::text
                    OR name LIKE auth.uid()::text || '/%'
                )
            );

        DROP POLICY IF EXISTS "Users can update their own payment proofs" ON storage.objects;
        CREATE POLICY "Users can update their own payment proofs"
            ON storage.objects FOR UPDATE TO authenticated
            USING (
                bucket_id = 'payment-proofs' 
                AND (
                    (storage.foldername(name))[1] = auth.uid()::text
                    OR name LIKE auth.uid()::text || '/%'
                )
            )
            WITH CHECK (
                bucket_id = 'payment-proofs' 
                AND (
                    (storage.foldername(name))[1] = auth.uid()::text
                    OR name LIKE auth.uid()::text || '/%'
                )
            );
    END IF;
END $$;

-- Automated updated_at Function & Triggers
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_users_updated_at ON public.users;
CREATE TRIGGER trigger_users_updated_at
    BEFORE UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

DROP TRIGGER IF EXISTS trigger_groups_updated_at ON public.groups;
CREATE TRIGGER trigger_groups_updated_at
    BEFORE UPDATE ON public.groups FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

DROP TRIGGER IF EXISTS trigger_tabs_updated_at ON public.tabs;
CREATE TRIGGER trigger_tabs_updated_at
    BEFORE UPDATE ON public.tabs FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

DROP TRIGGER IF EXISTS trigger_transactions_updated_at ON public.transactions;
CREATE TRIGGER trigger_transactions_updated_at
    BEFORE UPDATE ON public.transactions FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

DROP TRIGGER IF EXISTS trigger_recurring_rules_updated_at ON public.recurring_rules;
CREATE TRIGGER trigger_recurring_rules_updated_at
    BEFORE UPDATE ON public.recurring_rules FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- Activity Logging Triggers (Append-Only Audit Trail)
CREATE OR REPLACE FUNCTION public.log_transaction_activity()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        INSERT INTO public.activity_logs (
            actor_user_id,
            tab_id,
            transaction_id,
            event_type,
            metadata
        ) VALUES (
            NEW.created_by,
            NEW.tab_id,
            NEW.id,
            'DEBT_CREATED',
            jsonb_build_object(
                'total_amount_centavos', NEW.total_amount_centavos,
                'description', NEW.description,
                'category', NEW.category,
                'transaction_type', NEW.transaction_type
            )
        );
    ELSIF (TG_OP = 'UPDATE') THEN
        IF OLD.total_amount_centavos <> NEW.total_amount_centavos THEN
            INSERT INTO public.activity_logs (
                actor_user_id,
                tab_id,
                transaction_id,
                event_type,
                metadata
            ) VALUES (
                COALESCE(auth.uid(), NEW.created_by),
                NEW.tab_id,
                NEW.id,
                'AMOUNT_CHANGED',
                jsonb_build_object(
                    'old_amount_centavos', OLD.total_amount_centavos,
                    'new_amount_centavos', NEW.total_amount_centavos,
                    'description', NEW.description
                )
            );
        END IF;

        IF OLD.status <> 'cancelled' AND NEW.status = 'cancelled' THEN
            INSERT INTO public.activity_logs (
                actor_user_id,
                tab_id,
                transaction_id,
                event_type,
                metadata
            ) VALUES (
                COALESCE(auth.uid(), NEW.created_by),
                NEW.tab_id,
                NEW.id,
                'DEBT_CANCELLED',
                jsonb_build_object(
                    'total_amount_centavos', NEW.total_amount_centavos,
                    'description', NEW.description
                )
            );
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trigger_log_transaction ON public.transactions;
CREATE TRIGGER trigger_log_transaction
    AFTER INSERT OR UPDATE OF total_amount_centavos, status ON public.transactions
    FOR EACH ROW EXECUTE FUNCTION public.log_transaction_activity();

CREATE OR REPLACE FUNCTION public.log_payment_activity()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        INSERT INTO public.activity_logs (
            actor_user_id,
            tab_id,
            payment_id,
            event_type,
            metadata
        ) VALUES (
            NEW.submitted_by,
            NEW.tab_id,
            NEW.id,
            'PAYMENT_SUBMITTED',
            jsonb_build_object(
                'amount_centavos', NEW.amount_centavos,
                'payment_method', NEW.payment_method,
                'note', NEW.note
            )
        );
    ELSIF (TG_OP = 'UPDATE') THEN
        IF OLD.status <> 'confirmed' AND NEW.status = 'confirmed' THEN
            INSERT INTO public.activity_logs (
                actor_user_id,
                tab_id,
                payment_id,
                event_type,
                metadata
            ) VALUES (
                COALESCE(NEW.confirmed_by, auth.uid(), NEW.submitted_by),
                NEW.tab_id,
                NEW.id,
                'PAYMENT_CONFIRMED',
                jsonb_build_object(
                    'amount_centavos', NEW.amount_centavos,
                    'confirmed_by', NEW.confirmed_by,
                    'payment_method', NEW.payment_method
                )
            );
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trigger_log_payment ON public.payments;
CREATE TRIGGER trigger_log_payment
    AFTER INSERT OR UPDATE OF status ON public.payments
    FOR EACH ROW EXECUTE FUNCTION public.log_payment_activity();

CREATE OR REPLACE FUNCTION public.log_report_activity()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.activity_logs (
        actor_user_id,
        tab_id,
        transaction_id,
        payment_id,
        event_type,
        metadata
    ) VALUES (
        NEW.reported_by,
        NEW.tab_id,
        NEW.transaction_id,
        NEW.payment_id,
        'REPORT_CREATED',
        jsonb_build_object(
            'report_type', NEW.report_type,
            'message', NEW.message
        )
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trigger_log_report ON public.reports;
CREATE TRIGGER trigger_log_report
    AFTER INSERT ON public.reports
    FOR EACH ROW EXECUTE FUNCTION public.log_report_activity();

-- Split Validation Helper
CREATE OR REPLACE FUNCTION public.validate_transaction_split(p_transaction_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    v_total BIGINT;
    v_sum_shares BIGINT;
    v_tab_id UUID;
BEGIN
    SELECT total_amount_centavos, tab_id INTO v_total, v_tab_id
    FROM public.transactions
    WHERE id = p_transaction_id;

    IF v_total IS NULL THEN
        RETURN FALSE;
    END IF;

    IF auth.uid() IS NULL OR NOT public.is_tab_member(v_tab_id, auth.uid()) THEN
        RAISE EXCEPTION 'Not authorized to validate this transaction';
    END IF;

    SELECT COALESCE(SUM(share_amount_centavos), 0) INTO v_sum_shares
    FROM public.transaction_participants
    WHERE transaction_id = p_transaction_id
      AND participant_role IN ('debtor', 'beneficiary');

    RETURN v_total = v_sum_shares;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- ============================================================================
-- PART 5: AUTHORIZATION HARDENING
-- Kept in sync with migration 20260917000001_authz_hardening.sql.
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

ALTER FUNCTION public.is_tab_member(UUID, UUID) SET search_path = public, pg_temp;
ALTER FUNCTION public.is_group_member(UUID, UUID) SET search_path = public, pg_temp;
ALTER FUNCTION public.is_group_admin(UUID, UUID) SET search_path = public, pg_temp;
ALTER FUNCTION public.get_transaction_payer_id(UUID) SET search_path = public, pg_temp;
ALTER FUNCTION public.search_users(TEXT) SET search_path = public, pg_temp;
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
