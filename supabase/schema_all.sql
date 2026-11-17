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
    friend_code TEXT,
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
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'acknowledged', 'disputed', 'cancelled', 'settled')),
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
CREATE UNIQUE INDEX IF NOT EXISTS idx_transaction_one_payer
  ON public.transaction_participants (transaction_id)
  WHERE participant_role = 'payer';

-- 12. PAYMENTS TABLE
CREATE TABLE IF NOT EXISTS public.payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tab_id UUID NOT NULL REFERENCES public.tabs(id) ON DELETE CASCADE,
    submitted_by UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    recipient_user_id UUID REFERENCES public.users(id) ON DELETE RESTRICT,
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
CREATE INDEX IF NOT EXISTS idx_payments_recipient ON public.payments(recipient_user_id);
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
        COALESCE(NEW.phone, NEW.raw_user_meta_data->>'phone'),
        COALESCE(
            NEW.raw_user_meta_data->>'display_name',
            NEW.raw_user_meta_data->>'name',
            split_part(COALESCE(NEW.email, 'User'), '@', 1)
        ),
        NEW.raw_user_meta_data->>'avatar_url'
    )
    ON CONFLICT (id) DO UPDATE SET
        email = COALESCE(EXCLUDED.email, public.users.email),
        phone = COALESCE(EXCLUDED.phone, public.users.phone),
        display_name = COALESCE(NULLIF(EXCLUDED.display_name, ''), public.users.display_name),
        avatar_url = COALESCE(EXCLUDED.avatar_url, public.users.avatar_url),
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

CREATE OR REPLACE FUNCTION public.is_accepted_friend(
    p_user_a UUID,
    p_user_b UUID
)
RETURNS BOOLEAN AS $$
BEGIN
    IF p_user_a IS NULL OR p_user_b IS NULL OR p_user_a = p_user_b THEN
        RETURN FALSE;
    END IF;

    RETURN EXISTS (
        SELECT 1
        FROM public.friendships f
        WHERE f.status = 'accepted'
          AND (
              (f.requester_id = p_user_a AND f.addressee_id = p_user_b)
              OR (f.requester_id = p_user_b AND f.addressee_id = p_user_a)
          )
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
        (
            public.is_group_admin(group_id, auth.uid())
            OR (
                user_id = auth.uid()
                AND EXISTS (
                    SELECT 1 FROM public.groups g
                    WHERE g.id = group_id AND g.created_by = auth.uid()
                )
            )
        )
        AND EXISTS (
            SELECT 1
            FROM public.groups g
            WHERE g.id = group_id
              AND (
                  user_id = g.created_by
                  OR public.is_accepted_friend(g.created_by, user_id)
              )
        )
    );
DROP POLICY IF EXISTS "Group admins can update members or user can leave" ON public.group_members;
CREATE POLICY "Group admins can update members or user can leave"
    ON public.group_members FOR UPDATE TO authenticated
    USING (public.is_group_admin(group_id, auth.uid()) OR user_id = auth.uid())
    WITH CHECK (
        (public.is_group_admin(group_id, auth.uid()) OR user_id = auth.uid())
        AND EXISTS (
            SELECT 1
            FROM public.groups g
            WHERE g.id = group_id
              AND (
                  user_id = g.created_by
                  OR public.is_accepted_friend(g.created_by, user_id)
              )
        )
    );
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
DROP POLICY IF EXISTS "Tab admins or group creator can add tab members" ON public.tab_members;
CREATE POLICY "Tab admins or group creator can add tab members"
    ON public.tab_members FOR INSERT TO authenticated WITH CHECK (
        (
            EXISTS (
                SELECT 1 FROM public.tab_members admin
                WHERE admin.tab_id = tab_members.tab_id
                  AND admin.user_id = auth.uid()
                  AND admin.role = 'admin'
            )
            OR EXISTS (
                SELECT 1
                FROM public.tabs t
                JOIN public.groups g ON g.id = t.group_id
                WHERE t.id = tab_members.tab_id
                  AND g.created_by = auth.uid()
            )
        )
        AND (
            NOT EXISTS (
                SELECT 1 FROM public.tabs t
                WHERE t.id = tab_members.tab_id AND t.group_id IS NOT NULL
            )
            OR EXISTS (
                SELECT 1
                FROM public.tabs t
                JOIN public.groups g ON g.id = t.group_id
                WHERE t.id = tab_members.tab_id
                  AND (
                      tab_members.user_id = g.created_by
                      OR public.is_accepted_friend(g.created_by, tab_members.user_id)
                  )
            )
        )
    );
DROP POLICY IF EXISTS "Tab members can update tab membership" ON public.tab_members;
DROP POLICY IF EXISTS "Tab admins can update tab membership" ON public.tab_members;
CREATE POLICY "Tab admins can update tab membership"
    ON public.tab_members FOR UPDATE TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.tab_members admin
            WHERE admin.tab_id = tab_members.tab_id
              AND admin.user_id = auth.uid()
              AND admin.role = 'admin'
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.tab_members admin
            WHERE admin.tab_id = tab_members.tab_id
              AND admin.user_id = auth.uid()
              AND admin.role = 'admin'
        )
    );
DROP POLICY IF EXISTS "Tab members can remove members" ON public.tab_members;
DROP POLICY IF EXISTS "Tab admins or the member can remove membership" ON public.tab_members;
CREATE POLICY "Tab admins or the member can remove membership"
    ON public.tab_members FOR DELETE TO authenticated
    USING (
        user_id = auth.uid()
        OR EXISTS (
            SELECT 1 FROM public.tab_members admin
            WHERE admin.tab_id = tab_members.tab_id
              AND admin.user_id = auth.uid()
              AND admin.role = 'admin'
        )
    );

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
        DROP POLICY IF EXISTS "Tab members can upload payment proofs" ON storage.objects;
        DROP POLICY IF EXISTS "Uploaders can upload payment proofs" ON storage.objects;
        CREATE POLICY "Uploaders can upload payment proofs"
            ON storage.objects FOR INSERT TO authenticated
            WITH CHECK (
                bucket_id = 'payment-proofs'
                AND (storage.foldername(name))[1] = auth.uid()::text
            );

        DROP POLICY IF EXISTS "Authenticated users can view payment proofs" ON storage.objects;
        DROP POLICY IF EXISTS "Uploaders and tab counterparts can view payment proofs" ON storage.objects;
        CREATE POLICY "Uploaders and tab counterparts can view payment proofs"
            ON storage.objects FOR SELECT TO authenticated
            USING (
                bucket_id = 'payment-proofs'
                AND (
                    (storage.foldername(name))[1] = auth.uid()::text
                    OR EXISTS (
                        SELECT 1 FROM public.payment_proofs pp
                        JOIN public.payments p ON pp.payment_id = p.id
                        WHERE (pp.file_url = storage.objects.name OR pp.file_name = storage.objects.name)
                          AND public.is_tab_member(p.tab_id, auth.uid())
                    )
                    OR EXISTS (
                        SELECT 1 FROM public.transactions tx
                        WHERE tx.receipt_url = storage.objects.name
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
    v_all_shares BIGINT;
    v_payer_share BIGINT;
    v_debtor_shares BIGINT;
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

    SELECT
        COALESCE(SUM(share_amount_centavos), 0),
        COALESCE(SUM(share_amount_centavos)
            FILTER (WHERE participant_role = 'payer'), 0),
        COALESCE(SUM(share_amount_centavos)
            FILTER (WHERE participant_role IN ('debtor', 'beneficiary')), 0)
    INTO v_all_shares, v_payer_share, v_debtor_shares
    FROM public.transaction_participants
    WHERE transaction_id = p_transaction_id;

    RETURN v_all_shares = v_total
       AND v_debtor_shares = v_total - v_payer_share;
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
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid TEXT := auth.uid()::text;
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

    IF NEW.receipt_url IS DISTINCT FROM OLD.receipt_url
       AND NEW.receipt_url IS NOT NULL
       AND NEW.receipt_url <> '' THEN
        IF NEW.receipt_url ~* '^[a-z]+://' AND NEW.receipt_url !~* '^(file|content)://' THEN
            RAISE EXCEPTION 'Receipt attachments must be uploaded files';
        END IF;

        IF v_uid IS NOT NULL
           AND NEW.receipt_url NOT LIKE v_uid || '/%'
           AND left(NEW.receipt_url, 1) <> '/'
           AND NEW.receipt_url !~* '^(file|content)://'
           AND NEW.receipt_url !~ '^[A-Za-z]:[\\/]' THEN
            RAISE EXCEPTION 'Receipt attachments must belong to the uploader';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

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

-- ======================================================================
-- MONEY INTEGRITY HARDENING
-- ======================================================================

CREATE OR REPLACE FUNCTION public.calculate_user_tab_balance_unchecked(
    p_tab_id UUID,
    p_user_id UUID
)
RETURNS BIGINT AS $$
DECLARE
    v_owed_to_user BIGINT := 0;
    v_owed_by_user BIGINT := 0;
    v_paid_by_user BIGINT := 0;
    v_paid_to_user BIGINT := 0;
BEGIN
    SELECT COALESCE(SUM(tp.share_amount_centavos), 0)
    INTO v_owed_to_user
    FROM public.transactions t
    JOIN public.transaction_participants tp ON tp.transaction_id = t.id
    WHERE t.tab_id = p_tab_id
      AND t.status NOT IN ('cancelled', 'disputed')
      AND public.get_transaction_payer_id(t.id) = p_user_id
      AND tp.participant_role IN ('debtor', 'beneficiary')
      AND (tp.user_id IS NULL OR tp.user_id <> p_user_id);

    SELECT COALESCE(SUM(tp.share_amount_centavos), 0)
    INTO v_owed_by_user
    FROM public.transactions t
    JOIN public.transaction_participants tp ON tp.transaction_id = t.id
    WHERE t.tab_id = p_tab_id
      AND t.status NOT IN ('cancelled', 'disputed')
      AND public.get_transaction_payer_id(t.id) <> p_user_id
      AND tp.participant_role IN ('debtor', 'beneficiary')
      AND tp.user_id = p_user_id;

    SELECT COALESCE(SUM(p.amount_centavos), 0)
    INTO v_paid_by_user
    FROM public.payments p
    WHERE p.tab_id = p_tab_id
      AND p.status = 'confirmed'
      AND p.submitted_by = p_user_id;

    SELECT COALESCE(SUM(p.amount_centavos), 0)
    INTO v_paid_to_user
    FROM public.payments p
    WHERE p.tab_id = p_tab_id
      AND p.status = 'confirmed'
      AND (
          p.confirmed_by = p_user_id OR
          (p.submitted_by <> p_user_id AND p.confirmed_by IS NULL)
      );

    RETURN v_owed_to_user - v_owed_by_user
        - v_paid_to_user + v_paid_by_user;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = public, pg_temp;

CREATE OR REPLACE FUNCTION public.prevent_payment_overpayment()
RETURNS TRIGGER AS $$
DECLARE
    v_balance BIGINT;
    v_outstanding BIGINT;
BEGIN
    PERFORM pg_advisory_xact_lock(hashtextextended(NEW.tab_id::TEXT, 0));
    IF NOT public.is_tab_member(NEW.tab_id, NEW.submitted_by) THEN
        RAISE EXCEPTION 'Payment submitter is not a member of this tab';
    END IF;

    -- Payments between a known pair are bounded by what that pair still owes;
    -- a tab-wide net can be smaller than a genuine bilateral debt.
    IF NEW.recipient_user_id IS NOT NULL THEN
        v_outstanding := public.get_pair_outstanding(
            NEW.tab_id,
            NEW.submitted_by,
            NEW.recipient_user_id
        );
        IF v_outstanding <= 0 OR NEW.amount_centavos > v_outstanding THEN
            RAISE EXCEPTION
                'Payment exceeds the outstanding balance between the two members';
        END IF;
        RETURN NEW;
    END IF;

    -- Legacy writers do not name a recipient, so fall back to the tab balance.
    v_balance := public.calculate_user_tab_balance_unchecked(
        NEW.tab_id,
        NEW.submitted_by
    );
    IF ABS(v_balance) < NEW.amount_centavos THEN
        RAISE EXCEPTION
            'Payment exceeds the outstanding tab balance for the submitter';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

DROP TRIGGER IF EXISTS trigger_prevent_payment_overpayment ON public.payments;
CREATE TRIGGER trigger_prevent_payment_overpayment
    BEFORE INSERT ON public.payments
    FOR EACH ROW EXECUTE FUNCTION public.prevent_payment_overpayment();
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

CREATE OR REPLACE FUNCTION public.remove_friend(p_friend_user_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    IF p_friend_user_id IS NULL OR p_friend_user_id = auth.uid() THEN
        RETURN FALSE;
    END IF;

    DELETE FROM public.friendships f
    WHERE f.status = 'accepted'
      AND (
          (f.requester_id = auth.uid() AND f.addressee_id = p_friend_user_id)
          OR (f.requester_id = p_friend_user_id AND f.addressee_id = auth.uid())
      );

    RETURN FOUND;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

ALTER FUNCTION public.find_user_by_friend_code(TEXT) SET search_path = public, pg_temp;
ALTER FUNCTION public.send_friend_request(TEXT) SET search_path = public, pg_temp;
ALTER FUNCTION public.list_friend_requests() SET search_path = public, pg_temp;
ALTER FUNCTION public.respond_friend_request(UUID, BOOLEAN) SET search_path = public, pg_temp;
ALTER FUNCTION public.is_accepted_friend(UUID, UUID) SET search_path = public, pg_temp;
ALTER FUNCTION public.remove_friend(UUID) SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.find_user_by_friend_code(TEXT) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.send_friend_request(TEXT) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.list_friend_requests() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.respond_friend_request(UUID, BOOLEAN) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.is_accepted_friend(UUID, UUID) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.remove_friend(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.find_user_by_friend_code(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.send_friend_request(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_friend_requests() TO authenticated;
GRANT EXECUTE ON FUNCTION public.respond_friend_request(UUID, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_accepted_friend(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.remove_friend(UUID) TO authenticated;

-- Pending friendships must not make private user rows visible through SELECT.
DROP POLICY IF EXISTS "Users can view their own profile and connected parties" ON public.users;
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
CREATE POLICY "Requesters can cancel pending friendships"
    ON public.friendships FOR DELETE
    TO authenticated
    USING (requester_id = auth.uid() AND status = 'pending');

-- ============================================================================
-- PAYMENT METHODS (MIGRATION 20260917000005)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.payment_methods (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    provider TEXT NOT NULL CHECK (length(trim(provider)) > 0),
    display_name TEXT NOT NULL CHECK (length(trim(display_name)) > 0),
    account_label TEXT NOT NULL DEFAULT '',
    qr_storage_path TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    is_default BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_payment_methods_owner
    ON public.payment_methods(owner_user_id, is_active, created_at);
CREATE UNIQUE INDEX IF NOT EXISTS idx_payment_methods_one_default
    ON public.payment_methods(owner_user_id)
    WHERE is_active AND is_default;

ALTER TABLE public.payment_methods ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Owners can view their payment methods" ON public.payment_methods;
CREATE POLICY "Owners can view their payment methods"
    ON public.payment_methods FOR SELECT TO authenticated
    USING (owner_user_id = auth.uid());
DROP POLICY IF EXISTS "Owners can create payment methods" ON public.payment_methods;
CREATE POLICY "Owners can create payment methods"
    ON public.payment_methods FOR INSERT TO authenticated
    WITH CHECK (owner_user_id = auth.uid());
DROP POLICY IF EXISTS "Owners can update payment methods" ON public.payment_methods;
CREATE POLICY "Owners can update payment methods"
    ON public.payment_methods FOR UPDATE TO authenticated
    USING (owner_user_id = auth.uid()) WITH CHECK (owner_user_id = auth.uid());
DROP POLICY IF EXISTS "Owners can delete payment methods" ON public.payment_methods;
CREATE POLICY "Owners can delete payment methods"
    ON public.payment_methods FOR DELETE TO authenticated
    USING (owner_user_id = auth.uid());

CREATE OR REPLACE FUNCTION public.list_payment_methods_for_tab(
    p_tab_id UUID, p_payee_user_id UUID
)
RETURNS TABLE (
    id UUID, owner_user_id UUID, provider TEXT, display_name TEXT,
    account_label TEXT, qr_storage_path TEXT, is_active BOOLEAN,
    is_default BOOLEAN, created_at TIMESTAMPTZ, updated_at TIMESTAMPTZ
) AS $$
DECLARE v_balance BIGINT;
BEGIN
    IF auth.uid() IS NULL OR p_tab_id IS NULL OR p_payee_user_id IS NULL
       OR p_payee_user_id = auth.uid() THEN RETURN; END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.tabs t
        WHERE t.id = p_tab_id AND t.tab_type = 'individual'
          AND t.status = 'active'
          AND ((t.user_a = auth.uid() AND t.user_b = p_payee_user_id)
            OR (t.user_b = auth.uid() AND t.user_a = p_payee_user_id))
    ) THEN RETURN; END IF;
    v_balance := public.get_net_balance(p_tab_id, auth.uid());
    IF v_balance >= 0 THEN RETURN; END IF;
    RETURN QUERY SELECT pm.id, pm.owner_user_id, pm.provider, pm.display_name,
        pm.account_label, pm.qr_storage_path, pm.is_active, pm.is_default,
        pm.created_at, pm.updated_at
      FROM public.payment_methods pm
      WHERE pm.owner_user_id = p_payee_user_id AND pm.is_active
      ORDER BY pm.is_default DESC, pm.created_at ASC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public, pg_temp;
REVOKE EXECUTE ON FUNCTION public.list_payment_methods_for_tab(UUID, UUID)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_payment_methods_for_tab(UUID, UUID)
    TO authenticated;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'storage' AND table_name = 'buckets'
    ) THEN
        INSERT INTO storage.buckets
            (id, name, public, file_size_limit, allowed_mime_types)
        VALUES (
            'payment-methods', 'payment-methods', FALSE, 10485760,
            ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/jpg']
        )
        ON CONFLICT (id) DO UPDATE SET
            public = FALSE,
            file_size_limit = 10485760,
            allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/jpg'];

        DROP POLICY IF EXISTS "Owners can upload payment methods" ON storage.objects;
        CREATE POLICY "Owners can upload payment methods" ON storage.objects
            FOR INSERT TO authenticated
            WITH CHECK (bucket_id = 'payment-methods'
                AND (storage.foldername(name))[1] = auth.uid()::text);
        DROP POLICY IF EXISTS "Owners can update payment methods files" ON storage.objects;
        CREATE POLICY "Owners can update payment methods files" ON storage.objects
            FOR UPDATE TO authenticated
            USING (bucket_id = 'payment-methods'
                AND (storage.foldername(name))[1] = auth.uid()::text)
            WITH CHECK (bucket_id = 'payment-methods'
                AND (storage.foldername(name))[1] = auth.uid()::text);
        DROP POLICY IF EXISTS "Owners can delete payment methods files" ON storage.objects;
        CREATE POLICY "Owners can delete payment methods files" ON storage.objects
            FOR DELETE TO authenticated
            USING (bucket_id = 'payment-methods'
                AND (storage.foldername(name))[1] = auth.uid()::text);
        DROP POLICY IF EXISTS "Authorized debtors can view payment methods files" ON storage.objects;
        CREATE POLICY "Authorized debtors can view payment methods files" ON storage.objects
            FOR SELECT TO authenticated
            USING (bucket_id = 'payment-methods' AND EXISTS (
                SELECT 1 FROM public.payment_methods pm
                WHERE pm.qr_storage_path = name
                  AND (pm.owner_user_id = auth.uid() OR EXISTS (
                    SELECT 1 FROM public.tabs t
                    WHERE t.tab_type = 'individual' AND t.status = 'active'
                      AND ((t.user_a = auth.uid() AND t.user_b = pm.owner_user_id)
                        OR (t.user_b = auth.uid() AND t.user_a = pm.owner_user_id))
                      AND public.get_net_balance(t.id, auth.uid()) < 0
                  ))
            ));
    END IF;
END $$;

INSERT INTO public.payment_methods (
    owner_user_id, provider, display_name, account_label, qr_storage_path, is_default
)
SELECT u.id,
       CASE WHEN nullif(trim(u.gcash_number), '') IS NOT NULL THEN 'gcash'
            WHEN nullif(trim(u.maya_number), '') IS NOT NULL THEN 'maya'
            ELSE 'other' END,
       CASE WHEN nullif(trim(u.gcash_number), '') IS NOT NULL THEN 'GCash'
            WHEN nullif(trim(u.maya_number), '') IS NOT NULL THEN 'Maya'
            ELSE 'Payment QR' END,
       COALESCE(nullif(trim(u.gcash_number), ''), nullif(trim(u.maya_number), ''), ''),
       nullif(trim(u.qr_code_url), ''), TRUE
FROM public.users u
WHERE (nullif(trim(u.gcash_number), '') IS NOT NULL
    OR nullif(trim(u.maya_number), '') IS NOT NULL
    OR nullif(trim(u.qr_code_url), '') IS NOT NULL)
  AND NOT EXISTS (
      SELECT 1 FROM public.payment_methods pm WHERE pm.owner_user_id = u.id
  );

-- ============================================================================
-- ATOMIC MONEY CONTRACT (MIGRATION 20261029000001)
-- ============================================================================
ALTER TABLE public.payments
    ADD COLUMN IF NOT EXISTS recipient_user_id UUID REFERENCES public.users(id) ON DELETE RESTRICT;
CREATE INDEX IF NOT EXISTS idx_payments_recipient
    ON public.payments(recipient_user_id);

CREATE OR REPLACE FUNCTION public.log_payment_activity()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO public.activity_logs (
            actor_user_id, tab_id, payment_id, event_type, metadata
        ) VALUES (
            NEW.submitted_by, NEW.tab_id, NEW.id, 'PAYMENT_SUBMITTED',
            jsonb_build_object(
                'amount_centavos', NEW.amount_centavos,
                'payment_method', NEW.payment_method,
                'recipient_user_id', NEW.recipient_user_id,
                'note', NEW.note
            )
        );
    ELSIF TG_OP = 'UPDATE' AND OLD.status <> 'confirmed'
        AND NEW.status = 'confirmed' THEN
        INSERT INTO public.activity_logs (
            actor_user_id, tab_id, payment_id, event_type, metadata
        ) VALUES (
            COALESCE(NEW.confirmed_by, auth.uid(), NEW.submitted_by),
            NEW.tab_id, NEW.id, 'PAYMENT_CONFIRMED',
            jsonb_build_object(
                'amount_centavos', NEW.amount_centavos,
                'confirmed_by', NEW.confirmed_by,
                'recipient_user_id', NEW.recipient_user_id,
                'payment_method', NEW.payment_method
            )
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;
DROP TRIGGER IF EXISTS trigger_log_payment ON public.payments;
CREATE TRIGGER trigger_log_payment
    AFTER INSERT OR UPDATE OF status ON public.payments
    FOR EACH ROW EXECUTE FUNCTION public.log_payment_activity();

UPDATE public.payments
SET recipient_user_id = confirmed_by
WHERE recipient_user_id IS NULL AND confirmed_by IS NOT NULL;

CREATE OR REPLACE FUNCTION public.get_pair_outstanding(
    p_tab_id UUID, p_debtor_user_id UUID, p_payee_user_id UUID
)
RETURNS BIGINT AS $$
DECLARE
    v_owed_to_payee BIGINT := 0;
    v_owed_to_debtor BIGINT := 0;
    v_paid_to_payee BIGINT := 0;
    v_paid_to_debtor BIGINT := 0;
BEGIN
    IF p_tab_id IS NULL OR p_debtor_user_id IS NULL
       OR p_payee_user_id IS NULL OR p_debtor_user_id = p_payee_user_id THEN
        RETURN 0;
    END IF;
    SELECT COALESCE(SUM(tp.share_amount_centavos), 0) INTO v_owed_to_payee
    FROM public.transactions t
    JOIN public.transaction_participants tp ON tp.transaction_id = t.id
    WHERE t.tab_id = p_tab_id AND t.status NOT IN ('cancelled', 'disputed')
      AND public.get_transaction_payer_id(t.id) = p_payee_user_id
      AND tp.participant_role IN ('debtor', 'beneficiary')
      AND tp.user_id = p_debtor_user_id;
    SELECT COALESCE(SUM(tp.share_amount_centavos), 0) INTO v_owed_to_debtor
    FROM public.transactions t
    JOIN public.transaction_participants tp ON tp.transaction_id = t.id
    WHERE t.tab_id = p_tab_id AND t.status NOT IN ('cancelled', 'disputed')
      AND public.get_transaction_payer_id(t.id) = p_debtor_user_id
      AND tp.participant_role IN ('debtor', 'beneficiary')
      AND tp.user_id = p_payee_user_id;
    SELECT COALESCE(SUM(p.amount_centavos), 0) INTO v_paid_to_payee
    FROM public.payments p
    WHERE p.tab_id = p_tab_id AND p.status = 'confirmed'
      AND p.submitted_by = p_debtor_user_id
      AND p.recipient_user_id = p_payee_user_id;
    SELECT COALESCE(SUM(p.amount_centavos), 0) INTO v_paid_to_debtor
    FROM public.payments p
    WHERE p.tab_id = p_tab_id AND p.status = 'confirmed'
      AND p.submitted_by = p_payee_user_id
      AND p.recipient_user_id = p_debtor_user_id;
    RETURN GREATEST(
        v_owed_to_payee - v_owed_to_debtor - v_paid_to_payee + v_paid_to_debtor,
        0
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = public, pg_temp;

CREATE OR REPLACE FUNCTION public.create_expense_atomic(
    p_tab_id UUID, p_description TEXT, p_category TEXT,
    p_total_amount_centavos BIGINT, p_paid_by_user_id UUID,
    p_participants JSONB, p_due_date DATE DEFAULT NULL,
    p_receipt_url TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_transaction_id UUID;
    v_participant JSONB;
    v_payer_count INTEGER := 0;
    v_share_total BIGINT := 0;
    v_user_id UUID;
    v_contact_id UUID;
    v_role TEXT;
    v_share BIGINT;
BEGIN
    IF auth.uid() IS NULL OR NOT public.is_tab_member(p_tab_id, auth.uid()) THEN
        RAISE EXCEPTION 'Not authorized to create an expense for this tab';
    END IF;
    IF p_total_amount_centavos IS NULL OR p_total_amount_centavos <= 0 THEN
        RAISE EXCEPTION 'Expense amount must be greater than zero';
    END IF;
    IF p_paid_by_user_id IS NULL
       OR NOT public.is_tab_member(p_tab_id, p_paid_by_user_id) THEN
        RAISE EXCEPTION 'Payer must be a member of the tab';
    END IF;
    IF jsonb_typeof(p_participants) <> 'array'
       OR jsonb_array_length(p_participants) = 0 THEN
        RAISE EXCEPTION 'At least one participant is required';
    END IF;
    FOR v_participant IN SELECT value FROM jsonb_array_elements(p_participants)
    LOOP
        v_user_id := NULLIF(v_participant->>'user_id', '')::UUID;
        v_contact_id := NULLIF(v_participant->>'contact_id', '')::UUID;
        v_role := COALESCE(v_participant->>'participant_role', 'debtor');
        v_share := COALESCE((v_participant->>'share_amount_centavos')::BIGINT, -1);
        IF (v_user_id IS NULL) = (v_contact_id IS NULL) THEN
            RAISE EXCEPTION 'Each participant must identify exactly one user or contact';
        END IF;
        IF v_share < 0 THEN RAISE EXCEPTION 'Participant share cannot be negative'; END IF;
        IF v_role NOT IN ('payer', 'debtor', 'beneficiary') THEN
            RAISE EXCEPTION 'Invalid participant role';
        END IF;
        IF v_role = 'payer' THEN
            v_payer_count := v_payer_count + 1;
            IF v_user_id IS DISTINCT FROM p_paid_by_user_id THEN
                RAISE EXCEPTION 'Payer participant must match p_paid_by_user_id';
            END IF;
        END IF;
        IF v_user_id IS NOT NULL
           AND NOT public.is_tab_member(p_tab_id, v_user_id) THEN
            RAISE EXCEPTION 'User participant must be a member of the tab';
        END IF;
        IF v_contact_id IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM public.tab_members tm
            WHERE tm.tab_id = p_tab_id AND tm.contact_id = v_contact_id
        ) THEN
            RAISE EXCEPTION 'Contact participant must be a member of the tab';
        END IF;
        v_share_total := v_share_total + v_share;
    END LOOP;
    IF v_payer_count <> 1 THEN RAISE EXCEPTION 'Exactly one payer participant is required'; END IF;
    IF v_share_total <> p_total_amount_centavos THEN
        RAISE EXCEPTION 'Participant shares must equal the total expense amount';
    END IF;
    INSERT INTO public.transactions (
        tab_id, created_by, transaction_type, category, description,
        total_amount_centavos, currency, status, due_date, receipt_url
    ) VALUES (
        p_tab_id, auth.uid(), 'shared_expense',
        COALESCE(NULLIF(trim(p_category), ''), 'other'),
        COALESCE(NULLIF(trim(p_description), ''), 'Expense'),
        p_total_amount_centavos, 'PHP', 'acknowledged', p_due_date, p_receipt_url
    ) RETURNING id INTO v_transaction_id;
    INSERT INTO public.transaction_participants (
        transaction_id, user_id, contact_id, participant_role,
        share_amount_centavos, acknowledged
    )
    SELECT v_transaction_id, NULLIF(value->>'user_id', '')::UUID,
        NULLIF(value->>'contact_id', '')::UUID,
        COALESCE(value->>'participant_role', 'debtor'),
        (value->>'share_amount_centavos')::BIGINT,
        COALESCE((value->>'acknowledged')::BOOLEAN, false)
    FROM jsonb_array_elements(p_participants);
    RETURN v_transaction_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

CREATE OR REPLACE FUNCTION public.submit_payment(
    p_tab_id UUID, p_submitted_by_user_id UUID, p_recipient_user_id UUID,
    p_amount_centavos BIGINT, p_payment_method TEXT, p_note TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_submitter UUID := auth.uid();
    v_payment_id UUID;
    v_status TEXT := 'submitted';
    v_confirmed_by UUID := NULL;
    v_outstanding BIGINT;
BEGIN
    IF v_submitter IS NULL OR p_submitted_by_user_id IS NULL
       OR p_recipient_user_id IS NULL
       OR p_submitted_by_user_id = p_recipient_user_id
       OR (v_submitter <> p_submitted_by_user_id
           AND v_submitter <> p_recipient_user_id)
       OR NOT public.is_tab_member(p_tab_id, p_submitted_by_user_id)
       OR NOT public.is_tab_member(p_tab_id, p_recipient_user_id) THEN
        RAISE EXCEPTION 'Payment parties must be distinct members of the tab';
    END IF;
    IF p_amount_centavos IS NULL OR p_amount_centavos <= 0 THEN
        RAISE EXCEPTION 'Payment amount must be greater than zero';
    END IF;
    IF p_payment_method NOT IN ('gcash', 'maya', 'cash', 'bank_transfer', 'other') THEN
        RAISE EXCEPTION 'Invalid payment method';
    END IF;
    v_outstanding := public.get_pair_outstanding(
        p_tab_id, p_submitted_by_user_id, p_recipient_user_id
    );
    IF v_outstanding <= 0 OR p_amount_centavos > v_outstanding THEN
        RAISE EXCEPTION 'Payment exceeds the outstanding balance';
    END IF;
    IF v_submitter = p_recipient_user_id THEN
        v_status := 'confirmed';
        v_confirmed_by := v_submitter;
    END IF;
    INSERT INTO public.payments (
        tab_id, submitted_by, recipient_user_id, amount_centavos,
        payment_method, note, status, confirmed_by, confirmed_at
    ) VALUES (
        p_tab_id, p_submitted_by_user_id, p_recipient_user_id,
        p_amount_centavos, p_payment_method, p_note, v_status,
        v_confirmed_by, CASE WHEN v_confirmed_by IS NULL THEN NULL ELSE now() END
    ) RETURNING id INTO v_payment_id;
    RETURN v_payment_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

CREATE OR REPLACE FUNCTION public.confirm_payment(p_payment_id UUID)
RETURNS UUID AS $$
DECLARE
    v_payment public.payments%ROWTYPE;
    v_outstanding BIGINT;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
    SELECT * INTO v_payment FROM public.payments
    WHERE id = p_payment_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Payment not found'; END IF;
    IF v_payment.status <> 'submitted' THEN
        RAISE EXCEPTION 'Only submitted payments can be confirmed';
    END IF;
    IF v_payment.recipient_user_id IS DISTINCT FROM auth.uid() THEN
        RAISE EXCEPTION 'Only the payment recipient can confirm this payment';
    END IF;
    v_outstanding := public.get_pair_outstanding(
        v_payment.tab_id, v_payment.submitted_by, v_payment.recipient_user_id
    );
    IF v_payment.amount_centavos > v_outstanding THEN
        RAISE EXCEPTION 'Payment exceeds the outstanding balance';
    END IF;
    UPDATE public.payments
    SET status = 'confirmed', confirmed_by = auth.uid(), confirmed_at = now()
    WHERE id = p_payment_id AND status = 'submitted';
    RETURN p_payment_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

REVOKE ALL ON FUNCTION public.get_pair_outstanding(UUID, UUID, UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.create_expense_atomic(UUID, TEXT, TEXT, BIGINT, UUID, JSONB, DATE, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.submit_payment(UUID, UUID, UUID, BIGINT, TEXT, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.confirm_payment(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pair_outstanding(UUID, UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_expense_atomic(UUID, TEXT, TEXT, BIGINT, UUID, JSONB, DATE, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_payment(UUID, UUID, UUID, BIGINT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_payment(UUID) TO authenticated;

-- ============================================================================
-- Participant identity hardening
-- ============================================================================

CREATE OR REPLACE FUNCTION public.validate_transaction_participant_identity()
RETURNS TRIGGER AS $$
BEGIN
    IF (NEW.user_id IS NULL) = (NEW.contact_id IS NULL) THEN
        RAISE EXCEPTION 'Each participant must identify exactly one user or contact';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.transaction_participants existing
        WHERE existing.transaction_id = NEW.transaction_id
          AND (
              (NEW.user_id IS NOT NULL AND existing.user_id = NEW.user_id)
              OR
              (NEW.contact_id IS NOT NULL AND existing.contact_id = NEW.contact_id)
          )
    ) THEN
        RAISE EXCEPTION 'A transaction participant identity may appear only once';
    END IF;

    IF NEW.participant_role = 'payer'
       AND EXISTS (
           SELECT 1
           FROM public.transaction_participants existing
           WHERE existing.transaction_id = NEW.transaction_id
             AND (
                 (NEW.user_id IS NOT NULL AND existing.user_id = NEW.user_id)
                 OR
                 (NEW.contact_id IS NOT NULL AND existing.contact_id = NEW.contact_id)
             )
       ) THEN
        RAISE EXCEPTION 'A payer cannot also be another participant';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql
SET search_path = public, pg_temp;

DROP TRIGGER IF EXISTS trigger_validate_transaction_participant_identity
    ON public.transaction_participants;
CREATE TRIGGER trigger_validate_transaction_participant_identity
    BEFORE INSERT ON public.transaction_participants
    FOR EACH ROW
    EXECUTE FUNCTION public.validate_transaction_participant_identity();

ALTER FUNCTION public.validate_transaction_participant_identity()
    SET search_path = public, pg_temp;

REVOKE ALL ON FUNCTION public.validate_transaction_participant_identity()
    FROM PUBLIC, anon;

-- A row-level BEFORE trigger cannot see rows inserted earlier in the same
-- multi-row statement, which is how create_expense_atomic writes participants.
-- Re-check the whole transaction at commit time to close that window.
CREATE OR REPLACE FUNCTION public.assert_transaction_participant_identities()
RETURNS TRIGGER AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM public.transaction_participants
        WHERE transaction_id = NEW.transaction_id
        GROUP BY user_id, contact_id
        HAVING count(*) > 1
    ) THEN
        RAISE EXCEPTION 'A transaction participant identity may appear only once';
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

ALTER FUNCTION public.assert_transaction_participant_identities()
    SET search_path = public, pg_temp;

REVOKE ALL ON FUNCTION public.assert_transaction_participant_identities()
    FROM PUBLIC, anon;

DROP TRIGGER IF EXISTS trigger_assert_transaction_participant_identities
    ON public.transaction_participants;
CREATE CONSTRAINT TRIGGER trigger_assert_transaction_participant_identities
    AFTER INSERT ON public.transaction_participants
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
    EXECUTE FUNCTION public.assert_transaction_participant_identities();

-- ============================================================================
-- Authorization hardening (security report S1-S4, S7)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_or_create_contact_tab(
    p_owner_id uuid,
    p_contact_name text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
    v_contact_name TEXT := btrim(coalesce(p_contact_name, ''));
    v_contact_id UUID;
    v_tab_id UUID;
BEGIN
    IF auth.uid() IS NULL OR p_owner_id IS DISTINCT FROM auth.uid() THEN
        RAISE EXCEPTION 'Not authorized to create contact tabs for another user'
            USING ERRCODE = '42501';
    END IF;

    IF v_contact_name = '' THEN
        RAISE EXCEPTION 'Contact name is required' USING ERRCODE = '22023';
    END IF;

    SELECT id INTO v_contact_id
    FROM public.contacts
    WHERE owner_user_id = p_owner_id
      AND LOWER(display_name) = LOWER(v_contact_name)
    LIMIT 1;

    IF v_contact_id IS NULL THEN
        INSERT INTO public.contacts (owner_user_id, display_name)
        VALUES (p_owner_id, v_contact_name)
        RETURNING id INTO v_contact_id;
    END IF;

    SELECT tm.tab_id INTO v_tab_id
    FROM public.tab_members tm
    JOIN public.tabs t ON t.id = tm.tab_id
    WHERE tm.contact_id = v_contact_id
      AND t.tab_type = 'individual'
      AND t.status = 'active'
    LIMIT 1;

    IF v_tab_id IS NULL THEN
        INSERT INTO public.tabs (tab_type, status, user_a)
        VALUES ('individual', 'active', p_owner_id)
        RETURNING id INTO v_tab_id;

        INSERT INTO public.tab_members (tab_id, user_id, role)
        VALUES (v_tab_id, p_owner_id, 'admin');

        INSERT INTO public.tab_members (tab_id, contact_id, role)
        VALUES (v_tab_id, v_contact_id, 'participant');
    END IF;

    RETURN jsonb_build_object(
        'tab_id', v_tab_id,
        'contact_id', v_contact_id
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.get_or_create_contact_tab(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_or_create_contact_tab(uuid, text) TO authenticated;
-- SEC-002: this unchecked balance helper is an internal implementation detail.
-- SECURITY DEFINER payment RPCs execute it as their owner after authorizing
-- the caller. Mobile clients never call this function directly.
REVOKE ALL ON FUNCTION public.get_pair_outstanding(UUID, UUID, UUID)
    FROM PUBLIC, anon, authenticated;

-- Stable actor/operation identities survive response loss and concurrent retry.
CREATE TABLE public.financial_operations (
    actor_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    operation_id UUID NOT NULL,
    command_kind TEXT NOT NULL,
    command JSONB NOT NULL,
    result_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (actor_id, operation_id)
);
ALTER TABLE public.financial_operations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.financial_operations FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.execute_money_command_v1(
    p_operation_id UUID, p_kind TEXT, p_command JSONB
) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
    v_actor UUID := auth.uid();
    v_original public.financial_operations%ROWTYPE;
    v_result UUID;
BEGIN
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;
    IF p_operation_id IS NULL OR p_command IS NULL
       OR jsonb_typeof(p_command) <> 'object' THEN
        RAISE EXCEPTION 'Operation ID and command object required' USING ERRCODE = '22023';
    END IF;
    IF NOT public.is_tab_member((p_command->>'p_tab_id')::UUID, v_actor) THEN
        RAISE EXCEPTION 'Tab membership required' USING ERRCODE = '42501';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtextextended(v_actor::TEXT || ':' || p_operation_id::TEXT, 0));
    SELECT * INTO v_original FROM public.financial_operations
        WHERE actor_id = v_actor AND operation_id = p_operation_id;
    IF FOUND THEN
        IF v_original.command_kind IS DISTINCT FROM p_kind
           OR v_original.command IS DISTINCT FROM p_command THEN
            RAISE EXCEPTION 'Operation ID reused with a different command' USING ERRCODE = '22023';
        END IF;
        RETURN v_original.result_id;
    END IF;
    IF p_kind = 'expense' THEN
        v_result := public.create_expense_atomic(
            (p_command->>'p_tab_id')::UUID, p_command->>'p_description',
            p_command->>'p_category', (p_command->>'p_total_amount_centavos')::BIGINT,
            (p_command->>'p_paid_by_user_id')::UUID, p_command->'p_participants',
            (p_command->>'p_due_date')::DATE, p_command->>'p_receipt_url');
    ELSIF p_kind = 'payment' THEN
        v_result := public.submit_payment(
            (p_command->>'p_tab_id')::UUID, (p_command->>'p_submitted_by_user_id')::UUID,
            (p_command->>'p_recipient_user_id')::UUID, (p_command->>'p_amount_centavos')::BIGINT,
            p_command->>'p_payment_method', p_command->>'p_note');
    ELSE
        RAISE EXCEPTION 'Unsupported money command' USING ERRCODE = '22023';
    END IF;
    INSERT INTO public.financial_operations(actor_id, operation_id, command_kind, command, result_id)
        VALUES (v_actor, p_operation_id, p_kind, p_command, v_result);
    RETURN v_result;
END;
$$;
CREATE FUNCTION public.create_expense_v1(p_operation_id UUID, p_command JSONB)
RETURNS UUID LANGUAGE sql SECURITY DEFINER SET search_path = public, pg_temp
AS $$ SELECT public.execute_money_command_v1(p_operation_id, 'expense', p_command); $$;
CREATE FUNCTION public.submit_payment_v1(p_operation_id UUID, p_command JSONB)
RETURNS UUID LANGUAGE sql SECURITY DEFINER SET search_path = public, pg_temp
AS $$ SELECT public.execute_money_command_v1(p_operation_id, 'payment', p_command); $$;
REVOKE ALL ON FUNCTION public.execute_money_command_v1(UUID, TEXT, JSONB) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.create_expense_v1(UUID, JSONB) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.submit_payment_v1(UUID, JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_expense_v1(UUID, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_payment_v1(UUID, JSONB) TO authenticated;
-- Legacy reads remain supported; legacy clients must upgrade to write safely.
REVOKE ALL ON FUNCTION public.create_expense_atomic(UUID, TEXT, TEXT, BIGINT, UUID, JSONB, DATE, TEXT)
    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.submit_payment(UUID, UUID, UUID, BIGINT, TEXT, TEXT)
    FROM PUBLIC, anon, authenticated;
REVOKE INSERT ON public.transactions, public.transaction_participants, public.payments
    FROM PUBLIC, anon, authenticated;

-- Contact identity is explicit; display names are labels, never lookup keys.
CREATE FUNCTION public.resolve_contact_tab_v1(p_contact_id UUID, p_display_name TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_owner UUID := auth.uid(); v_existing_owner UUID; v_tab UUID;
BEGIN
    IF v_owner IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='42501'; END IF;
    IF p_contact_id IS NULL OR btrim(coalesce(p_display_name,'')) = '' THEN
        RAISE EXCEPTION 'Contact identity and display name required' USING ERRCODE='22023';
    END IF;
    IF EXISTS(SELECT 1 FROM public.users WHERE id=p_contact_id) THEN
      RAISE EXCEPTION 'Contact identity conflicts with a registered party' USING ERRCODE='22023';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtextextended(p_contact_id::TEXT, 0));
    SELECT owner_user_id INTO v_existing_owner FROM public.contacts WHERE id=p_contact_id;
    IF FOUND AND v_existing_owner IS DISTINCT FROM v_owner THEN
        RAISE EXCEPTION 'Contact belongs to another account' USING ERRCODE='42501';
    END IF;
    IF NOT FOUND THEN
        INSERT INTO public.contacts(id,owner_user_id,display_name)
        VALUES(p_contact_id,v_owner,btrim(p_display_name));
    END IF;
    SELECT tm.tab_id INTO v_tab FROM public.tab_members tm JOIN public.tabs t ON t.id=tm.tab_id
        WHERE tm.contact_id=p_contact_id AND t.tab_type='individual' AND t.status='active';
    IF v_tab IS NULL THEN
        INSERT INTO public.tabs(tab_type,status,user_a) VALUES('individual','active',v_owner) RETURNING id INTO v_tab;
        INSERT INTO public.tab_members(tab_id,user_id,role) VALUES(v_tab,v_owner,'admin');
        INSERT INTO public.tab_members(tab_id,contact_id,role) VALUES(v_tab,p_contact_id,'participant');
    END IF;
    RETURN jsonb_build_object('contact_id',p_contact_id,'tab_id',v_tab);
END; $$;
REVOKE ALL ON FUNCTION public.resolve_contact_tab_v1(UUID,TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.resolve_contact_tab_v1(UUID,TEXT) TO authenticated;
DO $$ BEGIN
  IF to_regprocedure('public.get_or_create_contact_tab(uuid,text)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.get_or_create_contact_tab(UUID,TEXT) FROM PUBLIC,anon,authenticated;
  END IF;
END; $$;

ALTER TABLE public.payments
    ADD COLUMN payer_user_id UUID REFERENCES public.users(id) ON DELETE RESTRICT,
    ADD COLUMN payer_contact_id UUID REFERENCES public.contacts(id) ON DELETE RESTRICT,
    ADD COLUMN recipient_contact_id UUID REFERENCES public.contacts(id) ON DELETE RESTRICT,
    ADD CONSTRAINT payment_payer_namespace CHECK (payer_contact_id IS NULL OR payer_user_id IS NULL),
    ADD CONSTRAINT payment_recipient_namespace CHECK (recipient_contact_id IS NULL OR recipient_user_id IS NULL);

CREATE OR REPLACE FUNCTION public.get_transaction_payer_id(p_transaction_id UUID)
RETURNS UUID LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public, pg_temp AS $$
    SELECT coalesce((SELECT coalesce(tp.user_id,tp.contact_id) FROM public.transaction_participants tp
      WHERE tp.transaction_id=p_transaction_id AND tp.participant_role='payer'),
      (SELECT created_by FROM public.transactions WHERE id=p_transaction_id));
$$;

CREATE FUNCTION public.get_party_outstanding_internal(p_tab UUID,
    p_debtor_kind TEXT,p_debtor UUID,p_payee_kind TEXT,p_payee UUID)
RETURNS BIGINT LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public, pg_temp AS $$
    WITH owed AS (
      SELECT coalesce(sum(CASE
        WHEN coalesce(payer.user_id,payer.contact_id)=p_payee
          AND (CASE WHEN payer.contact_id IS NULL THEN 'user' ELSE 'contact' END)=p_payee_kind
          AND coalesce(share.user_id,share.contact_id)=p_debtor
          AND (CASE WHEN share.contact_id IS NULL THEN 'user' ELSE 'contact' END)=p_debtor_kind
          THEN share.share_amount_centavos
        WHEN coalesce(payer.user_id,payer.contact_id)=p_debtor
          AND (CASE WHEN payer.contact_id IS NULL THEN 'user' ELSE 'contact' END)=p_debtor_kind
          AND coalesce(share.user_id,share.contact_id)=p_payee
          AND (CASE WHEN share.contact_id IS NULL THEN 'user' ELSE 'contact' END)=p_payee_kind
          THEN -share.share_amount_centavos ELSE 0 END),0) amount
      FROM public.transactions tx
      JOIN public.transaction_participants payer ON payer.transaction_id=tx.id AND payer.participant_role='payer'
      JOIN public.transaction_participants share ON share.transaction_id=tx.id AND share.participant_role IN ('debtor','beneficiary')
      WHERE tx.tab_id=p_tab AND tx.status NOT IN ('cancelled','disputed')
    ), paid AS (
      SELECT coalesce(sum(CASE
        WHEN coalesce(pay.payer_contact_id,pay.payer_user_id,pay.submitted_by)=p_debtor
          AND (CASE WHEN pay.payer_contact_id IS NULL THEN 'user' ELSE 'contact' END)=p_debtor_kind
          AND coalesce(pay.recipient_contact_id,pay.recipient_user_id)=p_payee
          AND (CASE WHEN pay.recipient_contact_id IS NULL THEN 'user' ELSE 'contact' END)=p_payee_kind THEN pay.amount_centavos
        WHEN coalesce(pay.payer_contact_id,pay.payer_user_id,pay.submitted_by)=p_payee
          AND (CASE WHEN pay.payer_contact_id IS NULL THEN 'user' ELSE 'contact' END)=p_payee_kind
          AND coalesce(pay.recipient_contact_id,pay.recipient_user_id)=p_debtor
          AND (CASE WHEN pay.recipient_contact_id IS NULL THEN 'user' ELSE 'contact' END)=p_debtor_kind THEN -pay.amount_centavos ELSE 0 END),0) amount
      FROM public.payments pay WHERE pay.tab_id=p_tab AND pay.status='confirmed'
    ) SELECT greatest(owed.amount-paid.amount,0)::BIGINT FROM owed,paid;
$$;
REVOKE ALL ON FUNCTION public.get_party_outstanding_internal(UUID,TEXT,UUID,TEXT,UUID) FROM PUBLIC,anon,authenticated;

-- Explicit cash records for an owner's private, unregistered-contact ledger.
-- Registered-party submissions keep recipient verification via submit_payment_v1.
CREATE FUNCTION public.record_received_payment_v1(p_operation_id UUID,p_command JSONB)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
    v_actor UUID:=auth.uid(); v_tab UUID:=(p_command->>'p_tab_id')::UUID;
    v_payer UUID:=(p_command->'payer'->>'id')::UUID;
    v_recipient UUID:=(p_command->'recipient'->>'id')::UUID;
    v_pk TEXT:=p_command->'payer'->>'kind'; v_rk TEXT:=p_command->'recipient'->>'kind';
    v_amount BIGINT:=(p_command->>'amount_centavos')::BIGINT;
    v_contact UUID; v_result UUID; v_old public.financial_operations%ROWTYPE;
BEGIN
    IF v_actor IS NULL OR NOT public.is_tab_member(v_tab,v_actor) THEN
      RAISE EXCEPTION 'Tab membership required' USING ERRCODE='42501';
    END IF;
    IF p_operation_id IS NULL OR v_pk IS NULL OR v_rk IS NULL
       OR NOT ((v_pk='contact' AND v_rk='user' AND v_recipient=v_actor)
         OR (v_pk='user' AND v_rk='contact' AND v_payer=v_actor)) THEN
      RAISE EXCEPTION 'Record requires the owner and one contact' USING ERRCODE='22023';
    END IF;
    v_contact:=CASE WHEN v_pk='contact' THEN v_payer ELSE v_recipient END;
    IF NOT EXISTS(SELECT 1 FROM public.contacts c JOIN public.tab_members tm ON tm.contact_id=c.id
      JOIN public.tabs t ON t.id=tm.tab_id WHERE c.id=v_contact AND c.owner_user_id=v_actor
      AND tm.tab_id=v_tab AND t.tab_type='individual') THEN
      RAISE EXCEPTION 'Contact must belong to this private tab' USING ERRCODE='42501';
    END IF;
    IF v_amount IS NULL OR v_amount<=0 OR p_command->>'method' IS DISTINCT FROM 'cash' THEN
      RAISE EXCEPTION 'A positive cash record is required' USING ERRCODE='22023';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtextextended(v_actor::TEXT||':'||p_operation_id::TEXT,0));
    SELECT * INTO v_old FROM public.financial_operations WHERE actor_id=v_actor AND operation_id=p_operation_id;
    IF FOUND THEN
      IF v_old.command_kind<>'contact_payment' OR v_old.command IS DISTINCT FROM p_command THEN
        RAISE EXCEPTION 'Operation ID reused with a different command' USING ERRCODE='22023';
      END IF;
      RETURN v_old.result_id;
    END IF;
    PERFORM pg_advisory_xact_lock(hashtextextended(v_tab::TEXT,0));
    IF v_amount>public.get_party_outstanding_internal(v_tab,v_pk,v_payer,v_rk,v_recipient) THEN
      RAISE EXCEPTION 'Payment exceeds outstanding balance' USING ERRCODE='22023';
    END IF;
    INSERT INTO public.payments(tab_id,submitted_by,payer_user_id,payer_contact_id,
      recipient_user_id,recipient_contact_id,amount_centavos,payment_method,note,status,confirmed_by,confirmed_at)
    VALUES(v_tab,v_actor,CASE WHEN v_pk='user' THEN v_payer END,CASE WHEN v_pk='contact' THEN v_payer END,
      CASE WHEN v_rk='user' THEN v_recipient END,CASE WHEN v_rk='contact' THEN v_recipient END,
      v_amount,'cash',p_command->>'note','confirmed',v_actor,now()) RETURNING id INTO v_result;
    INSERT INTO public.financial_operations(actor_id,operation_id,command_kind,command,result_id)
      VALUES(v_actor,p_operation_id,'contact_payment',p_command,v_result);
    RETURN v_result;
END; $$;
REVOKE ALL ON FUNCTION public.record_received_payment_v1(UUID,JSONB) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.record_received_payment_v1(UUID,JSONB) TO authenticated;

-- Extend existing internal validators to contact parties atomically.
CREATE OR REPLACE FUNCTION public.create_expense_atomic(
    p_tab_id UUID,
    p_description TEXT,
    p_category TEXT,
    p_total_amount_centavos BIGINT,
    p_paid_by_user_id UUID,
    p_participants JSONB,
    p_due_date DATE DEFAULT NULL,
    p_receipt_url TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_transaction_id UUID;
    v_participant JSONB;
    v_payer_count INTEGER := 0;
    v_share_total BIGINT := 0;
    v_user_id UUID;
    v_contact_id UUID;
    v_role TEXT;
    v_share BIGINT;
BEGIN
    IF auth.uid() IS NULL OR NOT public.is_tab_member(p_tab_id, auth.uid()) THEN
        RAISE EXCEPTION 'Not authorized to create an expense for this tab';
    END IF;
    IF p_total_amount_centavos IS NULL OR p_total_amount_centavos <= 0 THEN
        RAISE EXCEPTION 'Expense amount must be greater than zero';
    END IF;
    IF p_paid_by_user_id IS NULL
       OR (NOT public.is_tab_member(p_tab_id, p_paid_by_user_id) AND NOT EXISTS (
          SELECT 1 FROM public.contacts c JOIN public.tab_members tm ON tm.contact_id=c.id
          JOIN public.tabs t ON t.id=tm.tab_id
          WHERE c.id=p_paid_by_user_id AND c.owner_user_id=auth.uid()
            AND tm.tab_id=p_tab_id AND t.tab_type='individual')) THEN
        RAISE EXCEPTION 'Payer must be a member of the tab';
    END IF;
    IF jsonb_typeof(p_participants) <> 'array'
       OR jsonb_array_length(p_participants) = 0 THEN
        RAISE EXCEPTION 'At least one participant is required';
    END IF;

    FOR v_participant IN SELECT value FROM jsonb_array_elements(p_participants)
    LOOP
        v_user_id := NULLIF(v_participant->>'user_id', '')::UUID;
        v_contact_id := NULLIF(v_participant->>'contact_id', '')::UUID;
        v_role := COALESCE(v_participant->>'participant_role', 'debtor');
        v_share := COALESCE((v_participant->>'share_amount_centavos')::BIGINT, -1);

        IF (v_user_id IS NULL) = (v_contact_id IS NULL) THEN
            RAISE EXCEPTION 'Each participant must identify exactly one user or contact';
        END IF;
        IF v_share < 0 THEN
            RAISE EXCEPTION 'Participant share cannot be negative';
        END IF;
        IF v_role NOT IN ('payer', 'debtor', 'beneficiary') THEN
            RAISE EXCEPTION 'Invalid participant role';
        END IF;
        IF v_role = 'payer' THEN
            v_payer_count := v_payer_count + 1;
            IF COALESCE(v_user_id,v_contact_id) IS DISTINCT FROM p_paid_by_user_id THEN
                RAISE EXCEPTION 'Payer participant must match p_paid_by_user_id';
            END IF;
        END IF;
        IF v_user_id IS NOT NULL
           AND NOT public.is_tab_member(p_tab_id, v_user_id) THEN
            RAISE EXCEPTION 'User participant must be a member of the tab';
        END IF;
        IF v_contact_id IS NOT NULL
           AND NOT EXISTS (
               SELECT 1 FROM public.tab_members tm JOIN public.contacts c ON c.id=tm.contact_id
               JOIN public.tabs t ON t.id=tm.tab_id
               WHERE tm.tab_id=p_tab_id AND tm.contact_id=v_contact_id
                 AND c.owner_user_id=auth.uid() AND t.tab_type='individual'
           ) THEN
            RAISE EXCEPTION 'Contact participant must be a member of the tab';
        END IF;
        v_share_total := v_share_total + v_share;
    END LOOP;

    IF v_payer_count <> 1 THEN
        RAISE EXCEPTION 'Exactly one payer participant is required';
    END IF;
    IF v_share_total <> p_total_amount_centavos THEN
        RAISE EXCEPTION 'Participant shares must equal the total expense amount';
    END IF;

    INSERT INTO public.transactions (
        tab_id, created_by, transaction_type, category, description,
        total_amount_centavos, currency, status, due_date, receipt_url
    ) VALUES (
        p_tab_id, auth.uid(), 'shared_expense',
        COALESCE(NULLIF(trim(p_category), ''), 'other'),
        COALESCE(NULLIF(trim(p_description), ''), 'Expense'),
        p_total_amount_centavos, 'PHP', 'acknowledged',
        p_due_date, p_receipt_url
    )
    RETURNING id INTO v_transaction_id;

    INSERT INTO public.transaction_participants (
        transaction_id, user_id, contact_id, participant_role,
        share_amount_centavos, acknowledged
    )
    SELECT
        v_transaction_id,
        NULLIF(value->>'user_id', '')::UUID,
        NULLIF(value->>'contact_id', '')::UUID,
        COALESCE(value->>'participant_role', 'debtor'),
        (value->>'share_amount_centavos')::BIGINT,
        COALESCE((value->>'acknowledged')::BOOLEAN, false)
    FROM jsonb_array_elements(p_participants);

    RETURN v_transaction_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;


CREATE OR REPLACE FUNCTION public.calculate_user_tab_balance_unchecked(
    p_tab_id UUID,
    p_user_id UUID
)
RETURNS BIGINT AS $$
DECLARE
    v_owed_to_user BIGINT := 0;
    v_owed_by_user BIGINT := 0;
    v_paid_by_user BIGINT := 0;
    v_paid_to_user BIGINT := 0;
BEGIN
    SELECT COALESCE(SUM(tp.share_amount_centavos), 0)
    INTO v_owed_to_user
    FROM public.transactions t
    JOIN public.transaction_participants tp ON tp.transaction_id = t.id
    WHERE t.tab_id = p_tab_id
      AND t.status NOT IN ('cancelled', 'disputed')
      AND public.get_transaction_payer_id(t.id) = p_user_id
      AND tp.participant_role IN ('debtor', 'beneficiary')
      AND (tp.user_id IS NULL OR tp.user_id <> p_user_id);

    SELECT COALESCE(SUM(tp.share_amount_centavos), 0)
    INTO v_owed_by_user
    FROM public.transactions t
    JOIN public.transaction_participants tp ON tp.transaction_id = t.id
    WHERE t.tab_id = p_tab_id
      AND t.status NOT IN ('cancelled', 'disputed')
      AND public.get_transaction_payer_id(t.id) <> p_user_id
      AND tp.participant_role IN ('debtor', 'beneficiary')
      AND tp.user_id = p_user_id;

    SELECT COALESCE(SUM(p.amount_centavos), 0)
    INTO v_paid_by_user
    FROM public.payments p
    WHERE p.tab_id = p_tab_id
      AND p.status = 'confirmed'
      AND p.payer_contact_id IS NULL AND COALESCE(p.payer_user_id,p.submitted_by) = p_user_id;

    SELECT COALESCE(SUM(p.amount_centavos), 0)
    INTO v_paid_to_user
    FROM public.payments p
    WHERE p.tab_id = p_tab_id
      AND p.status = 'confirmed'
      AND p.recipient_contact_id IS NULL
      AND COALESCE(p.recipient_user_id,p.confirmed_by) = p_user_id;

    RETURN v_owed_to_user - v_owed_by_user
        - v_paid_to_user + v_paid_by_user;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = public, pg_temp;


CREATE OR REPLACE FUNCTION public.prevent_payment_overpayment()
RETURNS TRIGGER AS $$
DECLARE
    v_balance BIGINT;
    v_outstanding BIGINT;
BEGIN
    PERFORM pg_advisory_xact_lock(
        hashtextextended(NEW.tab_id::TEXT, 0)
    );

    IF NEW.payer_contact_id IS NOT NULL OR NEW.recipient_contact_id IS NOT NULL THEN
        v_outstanding := public.get_party_outstanding_internal(NEW.tab_id,
          CASE WHEN NEW.payer_contact_id IS NULL THEN 'user' ELSE 'contact' END,
          COALESCE(NEW.payer_contact_id,NEW.payer_user_id,NEW.submitted_by),
          CASE WHEN NEW.recipient_contact_id IS NULL THEN 'user' ELSE 'contact' END,
          COALESCE(NEW.recipient_contact_id,NEW.recipient_user_id));
        IF v_outstanding <= 0 OR NEW.amount_centavos > v_outstanding THEN
            RAISE EXCEPTION 'Payment exceeds the outstanding balance';
        END IF;
        RETURN NEW;
    END IF;
    IF NOT public.is_tab_member(NEW.tab_id, NEW.submitted_by) THEN
        RAISE EXCEPTION 'Payment submitter is not a member of this tab';
    END IF;

    -- Payments between a known pair are bounded by what that pair still owes;
    -- a tab-wide net can be smaller than a genuine bilateral debt.
    IF NEW.recipient_user_id IS NOT NULL THEN
        v_outstanding := public.get_pair_outstanding(
            NEW.tab_id,
            NEW.submitted_by,
            NEW.recipient_user_id
        );
        IF v_outstanding <= 0 OR NEW.amount_centavos > v_outstanding THEN
            RAISE EXCEPTION
                'Payment exceeds the outstanding balance between the two members';
        END IF;
        RETURN NEW;
    END IF;

    -- Legacy writers do not name a recipient, so fall back to the tab balance.
    v_balance := public.calculate_user_tab_balance_unchecked(
        NEW.tab_id,
        NEW.submitted_by
    );

    IF ABS(v_balance) < NEW.amount_centavos THEN
        RAISE EXCEPTION
            'Payment exceeds the outstanding tab balance for the submitter';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

DROP TRIGGER IF EXISTS trigger_prevent_payment_overpayment
  ON public.payments;
CREATE TRIGGER trigger_prevent_payment_overpayment
  BEFORE INSERT ON public.payments
  FOR EACH ROW EXECUTE FUNCTION public.prevent_payment_overpayment();

CREATE OR REPLACE FUNCTION public.get_net_balance(p_tab_id UUID,p_user_id UUID)
RETURNS BIGINT LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path=public,pg_temp AS $$
BEGIN
  IF auth.uid() IS NULL OR p_user_id IS DISTINCT FROM auth.uid()
     OR NOT public.is_tab_member(p_tab_id,auth.uid()) THEN
    RAISE EXCEPTION 'Not authorized to view this tab balance' USING ERRCODE='42501';
  END IF;
  RETURN public.calculate_user_tab_balance_unchecked(p_tab_id,p_user_id);
END; $$;
REVOKE ALL ON FUNCTION public.get_net_balance(UUID,UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_net_balance(UUID,UUID) TO authenticated;


-- Atomic group creation (20261031000004)
-- One authenticated, retry-safe transaction creates the full group roster/tab.
CREATE TABLE public.group_creation_commands (
  actor_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  operation_id UUID NOT NULL,
  command JSONB NOT NULL,
  group_id UUID NOT NULL REFERENCES public.groups(id) ON DELETE RESTRICT,
  tab_id UUID NOT NULL REFERENCES public.tabs(id) ON DELETE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY(actor_id,operation_id)
);
ALTER TABLE public.group_creation_commands ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.group_creation_commands FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.create_group_v1(p_operation_id UUID,p_command JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_previous public.group_creation_commands%ROWTYPE;
  v_name TEXT := trim(p_command->>'name');
  v_members UUID[];
  v_group UUID;
  v_tab UUID;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE='42501';
  END IF;
  IF p_operation_id IS NULL OR p_command IS NULL OR jsonb_typeof(p_command)<>'object' THEN
    RAISE EXCEPTION 'Operation and command required' USING ERRCODE='22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('tabby-group:'||v_actor::TEXT||':'||p_operation_id::TEXT,0));
  SELECT * INTO v_previous FROM public.group_creation_commands
    WHERE actor_id=v_actor AND operation_id=p_operation_id;
  IF FOUND THEN
    IF v_previous.command IS DISTINCT FROM p_command THEN
      RAISE EXCEPTION 'Operation reused with different group details' USING ERRCODE='22023';
    END IF;
    RETURN jsonb_build_object('group_id',v_previous.group_id,'tab_id',v_previous.tab_id);
  END IF;
  IF v_name IS NULL OR length(v_name)<1 OR length(v_name)>80
     OR jsonb_typeof(p_command->'member_user_ids') IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'Group name and member list required' USING ERRCODE='22023';
  END IF;
  SELECT array_agg(value::UUID) INTO v_members
    FROM jsonb_array_elements_text(p_command->'member_user_ids');
  IF COALESCE(cardinality(v_members),0)<1 OR cardinality(v_members)>99
     OR v_actor=ANY(v_members) OR array_position(v_members,NULL) IS NOT NULL
     OR cardinality(v_members)<>(SELECT count(DISTINCT id) FROM unnest(v_members) id) THEN
    RAISE EXCEPTION 'Choose distinct registered friends' USING ERRCODE='22023';
  END IF;
  IF EXISTS (SELECT 1 FROM unnest(v_members) member_id WHERE NOT EXISTS (
    SELECT 1 FROM public.friendships f WHERE f.status='accepted' AND
      ((f.requester_id=v_actor AND f.addressee_id=member_id) OR
       (f.addressee_id=v_actor AND f.requester_id=member_id)))) THEN
    RAISE EXCEPTION 'Every group member must be an accepted friend' USING ERRCODE='42501';
  END IF;
  INSERT INTO public.groups(created_by,name) VALUES(v_actor,v_name) RETURNING id INTO v_group;
  INSERT INTO public.group_members(group_id,user_id,role,status)
    VALUES(v_group,v_actor,'admin','active');
  INSERT INTO public.group_members(group_id,user_id,role,status)
    SELECT v_group,id,'member','active' FROM unnest(v_members) id;
  INSERT INTO public.tabs(tab_type,group_id,status) VALUES('group',v_group,'active') RETURNING id INTO v_tab;
  INSERT INTO public.tab_members(tab_id,user_id,role) VALUES(v_tab,v_actor,'admin');
  INSERT INTO public.tab_members(tab_id,user_id,role)
    SELECT v_tab,id,'participant' FROM unnest(v_members) id;
  INSERT INTO public.group_creation_commands(actor_id,operation_id,command,group_id,tab_id)
    VALUES(v_actor,p_operation_id,p_command,v_group,v_tab);
  RETURN jsonb_build_object('group_id',v_group,'tab_id',v_tab);
END; $$;
REVOKE ALL ON FUNCTION public.create_group_v1(UUID,JSONB) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_group_v1(UUID,JSONB) TO authenticated;
-- Legacy multi-request creation cannot leave partially committed rosters.
REVOKE INSERT ON public.groups,public.group_members,public.tabs,public.tab_members
  FROM PUBLIC,anon,authenticated;
-- New/changed rows must fit the agreed PHP input range. NOT VALID preserves
-- historical rows for explicit review instead of rewriting financial history.
ALTER TABLE public.transactions ADD CONSTRAINT transaction_m1_amount_limit
  CHECK(total_amount_centavos<=99999999999) NOT VALID;
ALTER TABLE public.transaction_participants ADD CONSTRAINT participant_m1_amount_limit
  CHECK(share_amount_centavos<=99999999999) NOT VALID;
ALTER TABLE public.payments ADD CONSTRAINT payment_m1_amount_limit
  CHECK(amount_centavos<=99999999999) NOT VALID;
ALTER TABLE public.payments ADD COLUMN rejection_reason TEXT;
ALTER TABLE public.payments ADD COLUMN rejected_at TIMESTAMPTZ;
CREATE TABLE public.payment_decisions (
  payment_id UUID PRIMARY KEY REFERENCES public.payments(id) ON DELETE RESTRICT,
  actor_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  decision TEXT NOT NULL CHECK(decision IN ('confirmed','rejected')),
  reason TEXT,
  decided_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.payment_decisions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.payment_decisions FROM PUBLIC,anon,authenticated;
REVOKE UPDATE,DELETE ON public.payments FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.decide_payment_internal(p_payment_id UUID,p_confirm BOOLEAN,p_reason TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  v_actor UUID:=auth.uid();
  v_payment public.payments%ROWTYPE;
  v_tab UUID;
  v_outstanding BIGINT;
BEGIN
  IF v_actor IS NULL OR p_confirm IS NULL THEN
    RAISE EXCEPTION 'Authentication and decision required' USING ERRCODE='42501';
  END IF;
  SELECT tab_id INTO v_tab FROM public.payments WHERE id=p_payment_id;
  IF v_tab IS NULL THEN RAISE EXCEPTION 'Payment unavailable' USING ERRCODE='42501'; END IF;
  -- Same lock as submission/overpayment triggers. Acquire before the row lock
  -- and balance read so different pending rows cannot use the same balance.
  PERFORM pg_advisory_xact_lock(hashtextextended(v_tab::TEXT,0));
  SELECT * INTO v_payment FROM public.payments WHERE id=p_payment_id FOR UPDATE;
  IF v_payment.recipient_user_id IS DISTINCT FROM v_actor
     OR NOT public.is_tab_member(v_tab,v_actor) THEN
    RAISE EXCEPTION 'Only the recipient can decide this payment' USING ERRCODE='42501';
  END IF;
  IF p_confirm AND v_payment.status='confirmed' THEN RETURN p_payment_id; END IF;
  IF NOT p_confirm AND v_payment.status='rejected' AND
      v_payment.rejection_reason IS NOT DISTINCT FROM nullif(trim(p_reason),'') THEN RETURN p_payment_id; END IF;
  IF v_payment.status<>'submitted' THEN
    RAISE EXCEPTION 'Payment already has a different decision' USING ERRCODE='22023';
  END IF;
  IF p_confirm THEN
    v_outstanding:=public.get_party_outstanding_internal(v_tab,'user',
      COALESCE(v_payment.payer_user_id,v_payment.submitted_by),'user',v_actor);
    IF v_payment.amount_centavos>v_outstanding OR v_outstanding<=0 THEN
      RAISE EXCEPTION 'Payment exceeds remaining pair obligation' USING ERRCODE='22023';
    END IF;
    INSERT INTO public.payment_decisions(payment_id,actor_id,decision)
      VALUES(p_payment_id,v_actor,'confirmed');
    UPDATE public.payments SET status='confirmed',confirmed_by=v_actor,confirmed_at=now()
      WHERE id=p_payment_id;
  ELSE
    IF nullif(trim(p_reason),'') IS NULL OR length(p_reason)>500 THEN
      RAISE EXCEPTION 'A rejection reason of 1 to 500 characters is required' USING ERRCODE='22023';
    END IF;
    INSERT INTO public.payment_decisions(payment_id,actor_id,decision,reason)
      VALUES(p_payment_id,v_actor,'rejected',trim(p_reason));
    UPDATE public.payments SET status='rejected',rejection_reason=trim(p_reason),rejected_at=now()
      WHERE id=p_payment_id;
  END IF;
  RETURN p_payment_id;
END; $$;
REVOKE ALL ON FUNCTION public.decide_payment_internal(UUID,BOOLEAN,TEXT) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.confirm_payment(p_payment_id UUID)
RETURNS UUID LANGUAGE sql SECURITY DEFINER SET search_path=public,pg_temp AS $$
  SELECT public.decide_payment_internal(p_payment_id,true,NULL);
$$;
CREATE FUNCTION public.reject_payment_v1(p_payment_id UUID,p_reason TEXT)
RETURNS UUID LANGUAGE sql SECURITY DEFINER SET search_path=public,pg_temp AS $$
  SELECT public.decide_payment_internal(p_payment_id,false,p_reason);
$$;
REVOKE ALL ON FUNCTION public.confirm_payment(UUID),public.reject_payment_v1(UUID,TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.confirm_payment(UUID),public.reject_payment_v1(UUID,TEXT) TO authenticated;

CREATE FUNCTION public.require_explicit_wallet_confirmation()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
  IF NEW.status='confirmed' AND NEW.payment_method<>'cash' THEN
    RAISE EXCEPTION 'Wallet payments require submission and a specific recipient decision' USING ERRCODE='22023';
  END IF;
  RETURN NEW;
END; $$;
REVOKE ALL ON FUNCTION public.require_explicit_wallet_confirmation() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER require_explicit_wallet_confirmation BEFORE INSERT ON public.payments
  FOR EACH ROW EXECUTE FUNCTION public.require_explicit_wallet_confirmation();
ALTER TABLE public.payment_proofs ADD COLUMN operation_id UUID;
ALTER TABLE public.payment_proofs ADD COLUMN uploaded_by UUID REFERENCES public.users(id) ON DELETE RESTRICT;
ALTER TABLE public.payment_proofs ADD COLUMN reference TEXT;
CREATE UNIQUE INDEX payment_proof_operation ON public.payment_proofs(uploaded_by,operation_id)
  WHERE operation_id IS NOT NULL;
REVOKE INSERT,UPDATE,DELETE ON public.payment_proofs FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.can_view_payment_proofs(p_payment_id UUID)
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER STABLE SET search_path=public,pg_temp AS $$
  SELECT auth.uid() IS NOT NULL AND EXISTS(SELECT 1 FROM public.payments p WHERE p.id=p_payment_id
    AND public.is_tab_member(p.tab_id,auth.uid()) AND
    (COALESCE(p.payer_user_id,p.submitted_by)=auth.uid() OR p.recipient_user_id=auth.uid()));
$$;
REVOKE ALL ON FUNCTION public.can_view_payment_proofs(UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_view_payment_proofs(UUID) TO authenticated;
DROP POLICY IF EXISTS "Tab members can view payment proofs" ON public.payment_proofs;
CREATE POLICY "Payment parties can view proof revisions" ON public.payment_proofs FOR SELECT TO authenticated
  USING(public.can_view_payment_proofs(payment_id));
GRANT SELECT ON public.payment_proofs TO authenticated;

CREATE FUNCTION public.append_payment_proof_v1(p_operation_id UUID,p_command JSONB)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  v_actor UUID:=auth.uid();
  v_payment UUID:=(p_command->>'payment_id')::UUID;
  v_path TEXT:=COALESCE(p_command->>'proof_path','');
  v_reference TEXT:=nullif(trim(p_command->>'reference'),'');
  v_previous public.payment_proofs%ROWTYPE;
  v_result UUID;
BEGIN
  IF v_actor IS NULL OR NOT public.can_view_payment_proofs(v_payment) THEN
    RAISE EXCEPTION 'Only payment parties can attach proof' USING ERRCODE='42501';
  END IF;
  IF p_operation_id IS NULL OR (v_path='' AND v_reference IS NULL) OR length(v_reference)>200 THEN
    RAISE EXCEPTION 'Proof or reference and operation ID required' USING ERRCODE='22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('payment-proof:'||v_actor::TEXT||':'||p_operation_id::TEXT,0));
  SELECT * INTO v_previous FROM public.payment_proofs WHERE uploaded_by=v_actor AND operation_id=p_operation_id;
  IF FOUND THEN
    IF v_previous.payment_id IS DISTINCT FROM v_payment OR v_previous.file_url IS DISTINCT FROM v_path
       OR v_previous.reference IS DISTINCT FROM v_reference THEN
      RAISE EXCEPTION 'Proof operation reused with different content' USING ERRCODE='22023';
    END IF;
    RETURN v_previous.id;
  END IF;
  IF v_path<>'' AND (v_path NOT LIKE v_actor::TEXT||'/%' OR v_path ~ '(^|/)\.\.(/|$)' OR NOT EXISTS(
    SELECT 1 FROM storage.objects o WHERE o.bucket_id='payment-proofs' AND o.name=v_path)) THEN
    RAISE EXCEPTION 'Proof must reference your uploaded private object' USING ERRCODE='42501';
  END IF;
  INSERT INTO public.payment_proofs(payment_id,file_url,file_name,mime_type,operation_id,uploaded_by,reference)
    VALUES(v_payment,v_path,COALESCE(nullif(v_path,''),'Reference only'),
      CASE WHEN v_path='' THEN 'text/plain' ELSE 'image/*' END,p_operation_id,v_actor,v_reference)
    RETURNING id INTO v_result;
  RETURN v_result;
END; $$;
REVOKE ALL ON FUNCTION public.append_payment_proof_v1(UUID,JSONB) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.append_payment_proof_v1(UUID,JSONB) TO authenticated;

CREATE FUNCTION public.submit_payment_v2(p_operation_id UUID,p_command JSONB)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_payment UUID;
BEGIN
  v_payment:=public.execute_money_command_v1(p_operation_id,'payment',p_command);
  IF nullif(p_command->>'proof_path','') IS NOT NULL OR nullif(trim(p_command->>'reference'),'') IS NOT NULL THEN
    PERFORM public.append_payment_proof_v1(p_operation_id,jsonb_build_object('payment_id',v_payment,
      'proof_path',p_command->>'proof_path','reference',p_command->>'reference'));
  END IF;
  RETURN v_payment;
END; $$;
REVOKE ALL ON FUNCTION public.submit_payment_v2(UUID,JSONB) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.submit_payment_v2(UUID,JSONB) TO authenticated;

CREATE FUNCTION public.can_read_payment_proof_object(p_path TEXT)
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER STABLE SET search_path=public,pg_temp AS $$
  SELECT auth.uid() IS NOT NULL AND (
    p_path LIKE auth.uid()::TEXT||'/%' OR EXISTS(
      SELECT 1 FROM public.payment_proofs pp WHERE pp.file_url=p_path AND public.can_view_payment_proofs(pp.payment_id))
    OR EXISTS(SELECT 1 FROM public.transactions t WHERE t.receipt_url=p_path AND public.is_tab_member(t.tab_id,auth.uid())));
$$;
CREATE FUNCTION public.can_mutate_unreferenced_proof(p_path TEXT)
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER STABLE SET search_path=public,pg_temp AS $$
  SELECT auth.uid() IS NOT NULL AND p_path LIKE auth.uid()::TEXT||'/%'
    AND NOT EXISTS(SELECT 1 FROM public.payment_proofs pp WHERE pp.file_url=p_path)
    AND NOT EXISTS(SELECT 1 FROM public.transactions t WHERE t.receipt_url=p_path);
$$;
REVOKE ALL ON FUNCTION public.can_read_payment_proof_object(TEXT),public.can_mutate_unreferenced_proof(TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_read_payment_proof_object(TEXT),public.can_mutate_unreferenced_proof(TEXT) TO authenticated;
DO $$ BEGIN
  IF to_regclass('storage.objects') IS NOT NULL THEN
    DROP POLICY IF EXISTS "Authenticated users can view payment proofs" ON storage.objects;
    DROP POLICY IF EXISTS "Uploaders and tab counterparts can view payment proofs" ON storage.objects;
    DROP POLICY IF EXISTS "Users can update their own payment proofs" ON storage.objects;
    DROP POLICY IF EXISTS "Users can delete their own payment proofs" ON storage.objects;
    CREATE POLICY "Payment proof parties read exact objects" ON storage.objects FOR SELECT TO authenticated
      USING(bucket_id='payment-proofs' AND public.can_read_payment_proof_object(name));
    CREATE POLICY "Only unreferenced proof objects can change" ON storage.objects FOR UPDATE TO authenticated
      USING(bucket_id='payment-proofs' AND public.can_mutate_unreferenced_proof(name))
      WITH CHECK(bucket_id='payment-proofs' AND public.can_mutate_unreferenced_proof(name));
    CREATE POLICY "Only unreferenced proof objects can be deleted" ON storage.objects FOR DELETE TO authenticated
      USING(bucket_id='payment-proofs' AND public.can_mutate_unreferenced_proof(name));
  END IF;
END $$;
CREATE TABLE public.transaction_receipt_revisions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  transaction_id UUID NOT NULL REFERENCES public.transactions(id) ON DELETE RESTRICT,
  uploaded_by UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  operation_id UUID NOT NULL,
  storage_path TEXT NOT NULL,
  uploaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(uploaded_by,operation_id)
);
ALTER TABLE public.transaction_receipt_revisions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.transaction_receipt_revisions FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.transaction_receipt_revisions TO authenticated;
CREATE FUNCTION public.can_view_transaction_receipts(p_transaction_id UUID)
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER STABLE SET search_path=public,pg_temp AS $$
  SELECT auth.uid() IS NOT NULL AND EXISTS(SELECT 1 FROM public.transactions t
    WHERE t.id=p_transaction_id AND public.is_tab_member(t.tab_id,auth.uid()));
$$;
REVOKE ALL ON FUNCTION public.can_view_transaction_receipts(UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_view_transaction_receipts(UUID) TO authenticated;
CREATE POLICY "Tab members read receipt revisions" ON public.transaction_receipt_revisions FOR SELECT TO authenticated
  USING(public.can_view_transaction_receipts(transaction_id));
REVOKE UPDATE,DELETE ON public.transactions FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.append_transaction_receipt_v1(p_operation_id UUID,p_command JSONB)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  v_actor UUID:=auth.uid();
  v_transaction UUID:=(p_command->>'transaction_id')::UUID;
  v_path TEXT:=p_command->>'proof_path';
  v_previous public.transaction_receipt_revisions%ROWTYPE;
  v_result UUID;
BEGIN
  IF v_actor IS NULL OR NOT EXISTS(SELECT 1 FROM public.transactions t WHERE t.id=v_transaction
      AND public.is_tab_member(t.tab_id,v_actor)) THEN
    RAISE EXCEPTION 'Tab membership required' USING ERRCODE='42501';
  END IF;
  IF p_operation_id IS NULL OR nullif(v_path,'') IS NULL THEN
    RAISE EXCEPTION 'Operation and uploaded receipt required' USING ERRCODE='22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('transaction-receipt:'||v_actor::TEXT||':'||p_operation_id::TEXT,0));
  SELECT * INTO v_previous FROM public.transaction_receipt_revisions WHERE uploaded_by=v_actor AND operation_id=p_operation_id;
  IF FOUND THEN
    IF v_previous.transaction_id IS DISTINCT FROM v_transaction OR v_previous.storage_path IS DISTINCT FROM v_path THEN
      RAISE EXCEPTION 'Receipt operation reused with different content' USING ERRCODE='22023';
    END IF;
    RETURN v_previous.id;
  END IF;
  IF v_path NOT LIKE v_actor::TEXT||'/%' OR v_path ~ '(^|/)\.\.(/|$)' OR NOT EXISTS(
    SELECT 1 FROM storage.objects o WHERE o.bucket_id='payment-proofs' AND o.name=v_path) THEN
    RAISE EXCEPTION 'Receipt must reference your uploaded private object' USING ERRCODE='42501';
  END IF;
  INSERT INTO public.transaction_receipt_revisions(transaction_id,uploaded_by,operation_id,storage_path)
    VALUES(v_transaction,v_actor,p_operation_id,v_path) RETURNING id INTO v_result;
  RETURN v_result;
END; $$;
REVOKE ALL ON FUNCTION public.append_transaction_receipt_v1(UUID,JSONB) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.append_transaction_receipt_v1(UUID,JSONB) TO authenticated;

CREATE OR REPLACE FUNCTION public.can_read_payment_proof_object(p_path TEXT)
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER STABLE SET search_path=public,pg_temp AS $$
  SELECT auth.uid() IS NOT NULL AND (
    p_path LIKE auth.uid()::TEXT||'/%' OR EXISTS(
      SELECT 1 FROM public.payment_proofs pp WHERE pp.file_url=p_path AND public.can_view_payment_proofs(pp.payment_id))
    OR EXISTS(SELECT 1 FROM public.transactions t WHERE t.receipt_url=p_path AND public.is_tab_member(t.tab_id,auth.uid()))
    OR EXISTS(SELECT 1 FROM public.transaction_receipt_revisions r JOIN public.transactions t ON t.id=r.transaction_id
      WHERE r.storage_path=p_path AND public.is_tab_member(t.tab_id,auth.uid())));
$$;
CREATE OR REPLACE FUNCTION public.can_mutate_unreferenced_proof(p_path TEXT)
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER STABLE SET search_path=public,pg_temp AS $$
  SELECT auth.uid() IS NOT NULL AND p_path LIKE auth.uid()::TEXT||'/%'
    AND NOT EXISTS(SELECT 1 FROM public.payment_proofs pp WHERE pp.file_url=p_path)
    AND NOT EXISTS(SELECT 1 FROM public.transactions t WHERE t.receipt_url=p_path)
    AND NOT EXISTS(SELECT 1 FROM public.transaction_receipt_revisions r WHERE r.storage_path=p_path);
$$;

-- QR-002: row and private-object authorization share the same narrow contract.
-- Unchecked financial helpers remain inaccessible to mobile client roles.
BEGIN;

CREATE OR REPLACE FUNCTION public.can_read_payment_method(p_method_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, pg_temp AS $$
    SELECT auth.uid() IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.payment_methods pm
        WHERE pm.id = p_method_id AND (
            pm.owner_user_id = auth.uid()
            OR (pm.is_active AND (
                EXISTS (
                    SELECT 1 FROM public.friendships f WHERE f.status = 'accepted'
                    AND ((f.requester_id = auth.uid() AND f.addressee_id = pm.owner_user_id)
                      OR (f.addressee_id = auth.uid() AND f.requester_id = pm.owner_user_id))
                ) OR EXISTS (
                    SELECT 1 FROM public.tabs t
                    JOIN public.tab_members debtor ON debtor.tab_id = t.id AND debtor.user_id = auth.uid()
                    JOIN public.tab_members payee ON payee.tab_id = t.id AND payee.user_id = pm.owner_user_id
                    WHERE t.status = 'active'
                      AND public.get_pair_outstanding(t.id, auth.uid(), pm.owner_user_id) > 0
                )
            ))
        )
    );
$$;

CREATE OR REPLACE FUNCTION public.can_read_payment_method_file(p_name TEXT)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, pg_temp AS $$
    SELECT auth.uid() IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.payment_methods pm
        WHERE pm.qr_storage_path = p_name AND pm.is_active
          AND public.can_read_payment_method(pm.id)
    );
$$;

REVOKE ALL ON FUNCTION public.can_read_payment_method(UUID),
    public.can_read_payment_method_file(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_read_payment_method(UUID),
    public.can_read_payment_method_file(TEXT) TO authenticated;
GRANT SELECT ON public.payment_methods TO authenticated;

DROP POLICY IF EXISTS "Owners can view their payment methods" ON public.payment_methods;
CREATE POLICY "Authorized parties can view payment methods"
    ON public.payment_methods FOR SELECT TO authenticated
    USING (public.can_read_payment_method(id));

DROP POLICY IF EXISTS "Authorized debtors can view payment methods files" ON storage.objects;
CREATE POLICY "Authorized parties can view payment methods files"
    ON storage.objects FOR SELECT TO authenticated
    USING (bucket_id = 'payment-methods' AND public.can_read_payment_method_file(name));

CREATE OR REPLACE FUNCTION public.list_payment_methods_for_tab(
    p_tab_id UUID, p_payee_user_id UUID
)
RETURNS TABLE (
    id UUID, owner_user_id UUID, provider TEXT, display_name TEXT,
    account_label TEXT, qr_storage_path TEXT, is_active BOOLEAN,
    is_default BOOLEAN, created_at TIMESTAMPTZ, updated_at TIMESTAMPTZ
) LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, pg_temp AS $$
BEGIN
    IF auth.uid() IS NULL OR p_payee_user_id = auth.uid()
       OR NOT EXISTS (
            SELECT 1 FROM public.tabs t
            JOIN public.tab_members debtor ON debtor.tab_id = t.id AND debtor.user_id = auth.uid()
            JOIN public.tab_members payee ON payee.tab_id = t.id AND payee.user_id = p_payee_user_id
            WHERE t.id = p_tab_id AND t.status = 'active'
       ) OR public.get_pair_outstanding(p_tab_id, auth.uid(), p_payee_user_id) <= 0 THEN
        RETURN;
    END IF;
    RETURN QUERY SELECT pm.id, pm.owner_user_id, pm.provider, pm.display_name,
        pm.account_label, pm.qr_storage_path, pm.is_active, pm.is_default,
        pm.created_at, pm.updated_at
        FROM public.payment_methods pm
        WHERE pm.owner_user_id = p_payee_user_id AND pm.is_active
        ORDER BY pm.is_default DESC, pm.created_at, pm.id;
END;
$$;
REVOKE ALL ON FUNCTION public.list_payment_methods_for_tab(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_payment_methods_for_tab(UUID, UUID) TO authenticated;
COMMIT;

BEGIN;
ALTER TABLE public.payment_methods ADD COLUMN revision INTEGER NOT NULL DEFAULT 1;
CREATE TABLE public.payment_method_revisions (
    method_id UUID NOT NULL REFERENCES public.payment_methods(id) ON DELETE RESTRICT,
    owner_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    revision INTEGER NOT NULL, snapshot JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (method_id, revision)
);
CREATE TABLE public.payment_method_operations (
    actor_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    operation_id UUID NOT NULL, kind TEXT NOT NULL, command JSONB NOT NULL,
    result JSONB NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (actor_id,operation_id)
);
ALTER TABLE public.payment_method_revisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payment_method_operations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.payment_method_revisions,public.payment_method_operations FROM anon,authenticated;
CREATE POLICY "Owners can read method revisions" ON public.payment_method_revisions
    FOR SELECT TO authenticated USING (owner_user_id=auth.uid());
GRANT SELECT ON public.payment_method_revisions TO authenticated;

-- Repair preference gaps in nonfinancial method metadata, preserving an existing preference.
DO $$
DECLARE v_owner UUID; v_selected UUID;
BEGIN
    FOR v_owner IN SELECT DISTINCT owner_user_id FROM public.payment_methods WHERE is_active LOOP
        SELECT id INTO v_selected FROM public.payment_methods
            WHERE owner_user_id=v_owner AND is_active
            ORDER BY is_default DESC,created_at,id LIMIT 1;
        UPDATE public.payment_methods SET is_default=false WHERE owner_user_id=v_owner AND is_default;
        UPDATE public.payment_methods SET is_default=true WHERE id=v_selected;
    END LOOP;
END $$;
INSERT INTO public.payment_method_revisions(method_id,owner_user_id,revision,snapshot)
    SELECT id,owner_user_id,revision,to_jsonb(pm) FROM public.payment_methods pm;

CREATE OR REPLACE FUNCTION public.change_payment_method_v1(
    p_operation_id UUID, p_kind TEXT, p_command JSONB
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER
SET search_path=public,pg_temp AS $$
DECLARE
    v_actor UUID := auth.uid(); v_id UUID; v_previous public.payment_methods;
    v_current public.payment_methods; v_operation public.payment_method_operations;
    v_path TEXT; v_default BOOLEAN; v_result JSONB; v_successor UUID;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'Sign in required' USING ERRCODE='42501'; END IF;
    IF p_operation_id IS NULL OR p_kind IS NULL OR p_kind NOT IN ('save','prefer','remove')
       OR p_command IS NULL OR jsonb_typeof(p_command)<>'object' THEN
        RAISE EXCEPTION 'Invalid method command' USING ERRCODE='22023';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtextextended('payment-methods:'||v_actor::text,0));
    SELECT * INTO v_operation FROM public.payment_method_operations
        WHERE actor_id=v_actor AND operation_id=p_operation_id;
    IF FOUND THEN
        IF v_operation.kind<>p_kind OR v_operation.command<>p_command THEN
            RAISE EXCEPTION 'Operation payload conflict' USING ERRCODE='22023';
        END IF;
        RETURN v_operation.result;
    END IF;
    v_id := (p_command->>'method_id')::uuid;
    IF v_id IS NULL THEN RAISE EXCEPTION 'Method ID required' USING ERRCODE='22023'; END IF;
    SELECT * INTO v_previous FROM public.payment_methods WHERE id=v_id FOR UPDATE;
    IF FOUND AND v_previous.owner_user_id<>v_actor THEN
        RAISE EXCEPTION 'Method is not owned by caller' USING ERRCODE='42501';
    END IF;
    IF p_kind='save' THEN
        IF nullif(trim(p_command->>'provider'),'') IS NULL
           OR nullif(trim(p_command->>'display_name'),'') IS NULL THEN
            RAISE EXCEPTION 'Method name/provider required' USING ERRCODE='22023';
        END IF;
        IF (v_previous.id IS NULL AND p_command->>'expected_revision' IS NOT NULL)
           OR (v_previous.id IS NOT NULL AND (
             NOT v_previous.is_active OR p_command->>'expected_revision' IS NULL
             OR (p_command->>'expected_revision')::integer<>v_previous.revision)) THEN
            RAISE EXCEPTION 'Method changed; refresh before editing' USING ERRCODE='40001';
        END IF;
        v_path := nullif(p_command->>'qr_storage_path','');
        IF v_path IS NOT NULL AND (v_previous.id IS NULL OR v_path IS DISTINCT FROM v_previous.qr_storage_path) THEN
            IF split_part(v_path,'/',1)<>v_actor::text OR NOT EXISTS (
                SELECT 1 FROM storage.objects WHERE bucket_id='payment-methods' AND name=v_path
            ) THEN RAISE EXCEPTION 'Upload the receiving QR first' USING ERRCODE='42501'; END IF;
        END IF;
        v_default := coalesce((p_command->>'make_default')::boolean,false)
            OR coalesce(v_previous.is_default,false)
            OR NOT EXISTS (SELECT 1 FROM public.payment_methods WHERE owner_user_id=v_actor AND is_active);
        IF v_default THEN
            UPDATE public.payment_methods SET is_default=false,revision=revision+1,updated_at=now()
                WHERE owner_user_id=v_actor AND is_default AND id<>v_id;
        END IF;
        INSERT INTO public.payment_methods(id,owner_user_id,provider,display_name,account_label,
            qr_storage_path,is_default,revision)
        VALUES(v_id,v_actor,trim(p_command->>'provider'),trim(p_command->>'display_name'),
            coalesce(p_command->>'account_label',''),v_path,v_default,1)
        ON CONFLICT(id) DO UPDATE SET provider=EXCLUDED.provider,display_name=EXCLUDED.display_name,
            account_label=EXCLUDED.account_label,qr_storage_path=EXCLUDED.qr_storage_path,
            is_default=v_default,revision=payment_methods.revision+1,updated_at=now();
    ELSE
        IF v_previous.id IS NULL OR NOT v_previous.is_active THEN
            RAISE EXCEPTION 'Active method not found' USING ERRCODE='22023';
        END IF;
        IF p_kind='prefer' THEN
            UPDATE public.payment_methods SET is_default=false,revision=revision+1,updated_at=now()
                WHERE owner_user_id=v_actor AND is_default AND id<>v_id;
            UPDATE public.payment_methods SET is_default=true,revision=revision+1,updated_at=now() WHERE id=v_id;
        ELSE
            UPDATE public.payment_methods SET is_active=false,is_default=false,revision=revision+1,updated_at=now() WHERE id=v_id;
            IF v_previous.is_default THEN
                SELECT id INTO v_successor FROM public.payment_methods WHERE owner_user_id=v_actor AND is_active
                    ORDER BY created_at,id LIMIT 1;
                UPDATE public.payment_methods SET is_default=true,revision=revision+1,updated_at=now() WHERE id=v_successor;
            END IF;
        END IF;
    END IF;
    SELECT * INTO v_current FROM public.payment_methods WHERE id=v_id;
    -- Record every metadata row changed by this command, including promotion/demotion.
    INSERT INTO public.payment_method_revisions(method_id,owner_user_id,revision,snapshot)
        SELECT id,owner_user_id,revision,to_jsonb(pm) FROM public.payment_methods pm
        WHERE owner_user_id=v_actor
        ON CONFLICT(method_id,revision) DO NOTHING;
    v_result := to_jsonb(v_current);
    INSERT INTO public.payment_method_operations(actor_id,operation_id,kind,command,result)
        VALUES(v_actor,p_operation_id,p_kind,p_command,v_result);
    RETURN v_result;
END $$;
REVOKE ALL ON FUNCTION public.change_payment_method_v1(UUID,TEXT,JSONB) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.change_payment_method_v1(UUID,TEXT,JSONB) TO authenticated;
REVOKE INSERT,UPDATE,DELETE ON public.payment_methods FROM anon,authenticated;

-- Replacement always uses a new object path; referenced revisions stay immutable.
CREATE OR REPLACE FUNCTION public.is_payment_method_file_referenced(p_name TEXT)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
    SELECT EXISTS(SELECT 1 FROM public.payment_methods WHERE qr_storage_path=p_name)
       OR EXISTS(SELECT 1 FROM public.payment_method_revisions WHERE snapshot->>'qr_storage_path'=p_name);
$$;
REVOKE ALL ON FUNCTION public.is_payment_method_file_referenced(TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.is_payment_method_file_referenced(TEXT) TO authenticated;
DROP POLICY IF EXISTS "Owners can update payment methods files" ON storage.objects;
DROP POLICY IF EXISTS "Owners can delete payment methods files" ON storage.objects;
CREATE POLICY "Owners can delete unreferenced method files" ON storage.objects
    FOR DELETE TO authenticated USING (bucket_id='payment-methods'
      AND split_part(name,'/',1)=auth.uid()::text AND NOT public.is_payment_method_file_referenced(name));
COMMIT;


-- HOME-004: exactly one accepted reminder per actor/operation. No client insert
-- fallback: an ambiguous network response is retried with the same operation ID.
CREATE TABLE public.reminder_operations (
  actor_id uuid NOT NULL REFERENCES public.users(id),
  operation_id uuid NOT NULL,
  command jsonb NOT NULL,
  notification_id uuid NOT NULL REFERENCES public.notifications(id),
  accepted_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(actor_id, operation_id)
);
ALTER TABLE public.reminder_operations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.reminder_operations FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.send_tab_reminder_v1(p_operation_id uuid, p_command jsonb)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  actor uuid := auth.uid();
  previous public.reminder_operations%ROWTYPE;
  v_tab_id uuid;
  recipient uuid;
  result uuid;
BEGIN
  IF actor IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='42501'; END IF;
  IF p_operation_id IS NULL OR p_command IS NULL OR jsonb_typeof(p_command)<>'object' THEN
    RAISE EXCEPTION 'Reminder command required' USING ERRCODE='22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':reminder',0));
  SELECT * INTO previous FROM public.reminder_operations
    WHERE actor_id=actor AND operation_id=p_operation_id;
  IF FOUND THEN
    IF previous.command<>p_command THEN RAISE EXCEPTION 'Operation payload conflict' USING ERRCODE='22023'; END IF;
    RETURN previous.notification_id;
  END IF;
  v_tab_id := (p_command->>'tab_id')::uuid;
  recipient := (p_command->>'recipient_user_id')::uuid;
  IF recipient IS NULL OR recipient=actor OR NOT EXISTS (
      SELECT 1 FROM public.tabs t JOIN public.tab_members a ON a.tab_id=t.id
      JOIN public.tab_members b ON b.tab_id=t.id WHERE t.id=v_tab_id
      AND t.status='active' AND a.user_id=actor AND b.user_id=recipient
      AND (t.group_id IS NULL OR (
        EXISTS(SELECT 1 FROM public.group_members g WHERE g.group_id=t.group_id AND g.user_id=actor AND g.status='active')
        AND EXISTS(SELECT 1 FROM public.group_members g WHERE g.group_id=t.group_id AND g.user_id=recipient AND g.status='active')))) THEN
    RAISE EXCEPTION 'Active shared tab required' USING ERRCODE='42501';
  END IF;
  IF public.get_pair_outstanding(v_tab_id,recipient,actor)<=0 THEN
    RAISE EXCEPTION 'Recipient has no outstanding obligation to sender' USING ERRCODE='22023';
  END IF;
  IF coalesce(length(btrim(p_command->>'title')),0) NOT BETWEEN 1 AND 120 OR
     coalesce(length(btrim(p_command->>'body')),0) NOT BETWEEN 1 AND 1000 THEN
    RAISE EXCEPTION 'Reminder title/body invalid' USING ERRCODE='22023';
  END IF;
  IF EXISTS (SELECT 1 FROM public.reminder_operations r WHERE r.actor_id=actor
      AND r.command->>'tab_id'=v_tab_id::text AND r.command->>'recipient_user_id'=recipient::text
      AND r.accepted_at>now()-interval '1 minute') THEN
    RAISE EXCEPTION 'Please wait before sending another reminder' USING ERRCODE='22023';
  END IF;
  INSERT INTO public.notifications(recipient_user_id,notification_type,related_tab_id,title,body)
    VALUES(recipient,'manual_nudge',v_tab_id,btrim(p_command->>'title'),btrim(p_command->>'body'))
    RETURNING id INTO result;
  INSERT INTO public.activity_logs(id,actor_user_id,tab_id,event_type,metadata)
    VALUES(result,actor,v_tab_id,'REMINDER_SENT',jsonb_build_object('recipient_id',recipient,'notification_id',result));
  INSERT INTO public.reminder_operations(actor_id,operation_id,command,notification_id)
    VALUES(actor,p_operation_id,p_command,result);
  RETURN result;
END; $$;
REVOKE ALL ON FUNCTION public.send_tab_reminder_v1(uuid,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.send_tab_reminder_v1(uuid,jsonb) TO authenticated;
DO $$ BEGIN
  IF to_regprocedure('public.send_tab_reminder(uuid,uuid,text,text)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.send_tab_reminder(uuid,uuid,text,text) FROM PUBLIC,anon,authenticated;
  END IF;
END $$;
DROP POLICY IF EXISTS "Tab members can queue reminders" ON public.notifications;


-- HOME-004: private account-bound endpoints and leased background delivery jobs.
-- Tokens never appear in user-readable tables, activity metadata or app logs.
CREATE TABLE public.push_device_bindings (
  installation_id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  binding_id uuid NOT NULL,
  token text NOT NULL CHECK(length(token) BETWEEN 20 AND 4096),
  reminders_enabled boolean NOT NULL DEFAULT false,
  expires_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX push_device_token_unique ON public.push_device_bindings(token);
CREATE TABLE public.push_delivery_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  notification_id uuid NOT NULL REFERENCES public.notifications(id) ON DELETE CASCADE,
  installation_id uuid NOT NULL,
  binding_id uuid NOT NULL,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','sending','accepted','cancelled','failed')),
  token_hash text NOT NULL,
  attempts integer NOT NULL DEFAULT 0,
  next_attempt_at timestamptz NOT NULL DEFAULT now(),
  lease_id uuid,
  lease_until timestamptz,
  error_code text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(notification_id,installation_id,binding_id)
);
CREATE INDEX push_jobs_ready ON public.push_delivery_jobs(next_attempt_at) WHERE status IN ('pending','sending');
ALTER TABLE public.push_device_bindings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.push_delivery_jobs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.push_device_bindings,public.push_delivery_jobs FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.register_push_device_v1(p_installation_id uuid,p_binding_id uuid,p_token text,p_reminders_enabled boolean)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE actor uuid:=auth.uid();
BEGIN
  IF actor IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='42501'; END IF;
  IF p_installation_id IS NULL OR p_binding_id IS NULL OR p_reminders_enabled IS NULL
    OR coalesce(length(p_token),0) NOT BETWEEN 20 AND 4096 THEN
    RAISE EXCEPTION 'Invalid push registration' USING ERRCODE='22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('push:'||p_installation_id::text,0));
  -- A Firebase token can rotate/reappear under a restored installation. Only one
  -- active association is retained; neither endpoint nor token is client-readable.
  DELETE FROM public.push_device_bindings WHERE token=p_token AND installation_id<>p_installation_id;
  INSERT INTO public.push_device_bindings(installation_id,user_id,binding_id,token,reminders_enabled,expires_at)
    VALUES(p_installation_id,actor,p_binding_id,p_token,p_reminders_enabled,now()+interval '1 day')
    ON CONFLICT(installation_id) DO UPDATE SET user_id=EXCLUDED.user_id,binding_id=EXCLUDED.binding_id,
      token=EXCLUDED.token,reminders_enabled=EXCLUDED.reminders_enabled,expires_at=EXCLUDED.expires_at,updated_at=now();
  UPDATE public.push_delivery_jobs SET status='cancelled',lease_id=NULL,lease_until=NULL
    WHERE installation_id=p_installation_id AND status IN ('pending','sending')
    AND (binding_id<>p_binding_id OR user_id<>actor OR NOT p_reminders_enabled
      OR token_hash<>encode(sha256(convert_to(p_token,'UTF8')),'hex'));
  RETURN true;
END; $$;

CREATE FUNCTION public.revoke_push_device_v1(p_installation_id uuid,p_binding_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='42501'; END IF;
  DELETE FROM public.push_device_bindings WHERE installation_id=p_installation_id AND binding_id=p_binding_id AND user_id=auth.uid();
  IF NOT FOUND THEN RETURN false; END IF;
  UPDATE public.push_delivery_jobs SET status='cancelled',lease_id=NULL,lease_until=NULL
    WHERE installation_id=p_installation_id AND binding_id=p_binding_id AND status IN ('pending','sending');
  RETURN true;
END; $$;

CREATE FUNCTION public.enqueue_reminder_push_v1() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  IF NEW.notification_type IN ('manual_nudge','tab_reminder') THEN
    INSERT INTO public.push_delivery_jobs(notification_id,installation_id,binding_id,user_id,token_hash)
      SELECT NEW.id,d.installation_id,d.binding_id,d.user_id,encode(sha256(convert_to(d.token,'UTF8')),'hex') FROM public.push_device_bindings d
      WHERE d.user_id=NEW.recipient_user_id AND d.reminders_enabled AND d.expires_at>now()
      ON CONFLICT DO NOTHING;
  END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER enqueue_reminder_push AFTER INSERT ON public.notifications
  FOR EACH ROW EXECUTE FUNCTION public.enqueue_reminder_push_v1();

CREATE FUNCTION public.claim_reminder_push_v1(p_limit integer DEFAULT 50)
RETURNS TABLE(job_id uuid,lease_id uuid,notification_id uuid,user_id uuid,binding_id uuid,tab_id uuid,token text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  -- Remove stale associations before acquiring jobs. Native receivers also check
  -- the exact binding, covering messages already in flight during logout.
  UPDATE public.push_delivery_jobs j SET status='cancelled',lease_id=NULL,lease_until=NULL
    WHERE j.status IN ('pending','sending') AND NOT EXISTS (
      SELECT 1 FROM public.push_device_bindings d JOIN public.notifications n ON n.id=j.notification_id
      JOIN public.tabs t ON t.id=n.related_tab_id
      JOIN public.tab_members m ON m.tab_id=t.id AND m.user_id=d.user_id
      WHERE d.installation_id=j.installation_id AND d.binding_id=j.binding_id AND d.user_id=j.user_id
      AND j.token_hash=encode(sha256(convert_to(d.token,'UTF8')),'hex')
      AND d.user_id=n.recipient_user_id AND d.reminders_enabled AND d.expires_at>now() AND t.status='active'
      AND EXISTS(SELECT 1 FROM public.reminder_operations r WHERE r.notification_id=n.id
        AND public.get_pair_outstanding(t.id,d.user_id,r.actor_id)>0)
      AND (t.group_id IS NULL OR EXISTS(SELECT 1 FROM public.group_members g
        WHERE g.group_id=t.group_id AND g.user_id=d.user_id AND g.status='active')));
  UPDATE public.push_delivery_jobs j SET status='failed',error_code='retry_limit',lease_id=NULL,lease_until=NULL
    WHERE j.attempts>=6 AND (j.status='pending' OR (j.status='sending' AND j.lease_until<now()));
  RETURN QUERY WITH ready AS (
    SELECT j.id FROM public.push_delivery_jobs j
    WHERE (j.status='pending' AND j.next_attempt_at<=now()) OR (j.status='sending' AND j.lease_until<now())
    ORDER BY j.created_at,j.id FOR UPDATE SKIP LOCKED LIMIT least(greatest(p_limit,1),100)
  ), leased AS (
    UPDATE public.push_delivery_jobs j SET status='sending',attempts=j.attempts+1,
      lease_id=gen_random_uuid(),lease_until=now()+interval '2 minutes'
      FROM ready r WHERE j.id=r.id RETURNING j.*
  ) SELECT l.id,l.lease_id,l.notification_id,l.user_id,l.binding_id,n.related_tab_id,d.token
    FROM leased l JOIN public.push_device_bindings d ON d.installation_id=l.installation_id
      AND d.binding_id=l.binding_id AND d.user_id=l.user_id
    JOIN public.notifications n ON n.id=l.notification_id;
END; $$;

CREATE FUNCTION public.finish_reminder_push_v1(p_job_id uuid,p_lease_id uuid,p_outcome text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE job public.push_delivery_jobs%ROWTYPE;
BEGIN
  IF p_outcome IS NULL OR p_outcome NOT IN ('accepted','retry','unregistered','permanent') THEN
    RAISE EXCEPTION 'Invalid push outcome' USING ERRCODE='22023';
  END IF;
  SELECT * INTO job FROM public.push_delivery_jobs WHERE id=p_job_id AND lease_id=p_lease_id AND status='sending' FOR UPDATE;
  IF NOT FOUND THEN RETURN false; END IF;
  IF p_outcome='unregistered' THEN
    DELETE FROM public.push_device_bindings WHERE installation_id=job.installation_id AND binding_id=job.binding_id AND user_id=job.user_id;
  END IF;
  UPDATE public.push_delivery_jobs SET status=CASE WHEN p_outcome='accepted' THEN 'accepted'
      WHEN p_outcome='retry' AND attempts<6 THEN 'pending' ELSE 'failed' END,
    error_code=CASE WHEN p_outcome='accepted' THEN NULL ELSE p_outcome END,
    next_attempt_at=now()+make_interval(secs=>least(3600,(60*power(2,least(attempts,6)))::integer)),
    lease_id=NULL,lease_until=NULL WHERE id=job.id;
  RETURN true;
END; $$;
REVOKE ALL ON FUNCTION public.register_push_device_v1(uuid,uuid,text,boolean),public.revoke_push_device_v1(uuid,uuid),
  public.enqueue_reminder_push_v1(),public.claim_reminder_push_v1(integer),public.finish_reminder_push_v1(uuid,uuid,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.register_push_device_v1(uuid,uuid,text,boolean),public.revoke_push_device_v1(uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.claim_reminder_push_v1(integer),public.finish_reminder_push_v1(uuid,uuid,text) TO service_role;


-- AUTH-004: canonicalize new/explicitly changed profile phones. No bulk rewrite,
-- identity merging or guessed repair of historical duplicates is performed.
CREATE FUNCTION public.normalize_ph_mobile_v1(p_phone text) RETURNS text
LANGUAGE plpgsql IMMUTABLE SET search_path=public,pg_temp AS $$
DECLARE compact text;
BEGIN
  IF p_phone IS NULL OR btrim(p_phone) !~ '^\+?[0-9 ()-]+$' THEN RETURN NULL; END IF;
  compact:=regexp_replace(btrim(p_phone),'[ ()-]','','g');
  IF compact ~ '^09[0-9]{9}$' THEN RETURN '+63'||substring(compact from 2); END IF;
  IF compact ~ '^9[0-9]{9}$' THEN RETURN '+63'||compact; END IF;
  IF compact ~ '^\+?639[0-9]{9}$' THEN RETURN CASE WHEN left(compact,1)='+' THEN compact ELSE '+'||compact END; END IF;
  RETURN NULL;
END; $$;
CREATE FUNCTION public.canonical_profile_phone_v1() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE canonical text;
BEGIN
  IF TG_OP='UPDATE' AND NEW.phone IS NOT DISTINCT FROM OLD.phone THEN RETURN NEW; END IF;
  IF NEW.phone IS NULL OR btrim(NEW.phone)='' THEN RETURN NEW; END IF;
  canonical:=public.normalize_ph_mobile_v1(NEW.phone);
  IF canonical IS NULL THEN RAISE EXCEPTION 'Invalid Philippine mobile number' USING ERRCODE='22023'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('profile-phone:'||canonical,0));
  IF EXISTS(SELECT 1 FROM public.users u WHERE u.id<>NEW.id AND public.normalize_ph_mobile_v1(u.phone)=canonical) THEN
    RAISE EXCEPTION 'users_phone_canonical_conflict' USING ERRCODE='23505';
  END IF;
  NEW.phone:=canonical;RETURN NEW;
END; $$;
CREATE TRIGGER canonical_profile_phone BEFORE INSERT OR UPDATE OF phone ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.canonical_profile_phone_v1();
CREATE OR REPLACE FUNCTION public.is_phone_available(p_phone text,p_user_id uuid DEFAULT NULL)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE canonical text:=public.normalize_ph_mobile_v1(p_phone);
BEGIN
  IF canonical IS NULL THEN RETURN false; END IF;
  RETURN NOT EXISTS(SELECT 1 FROM public.users u WHERE public.normalize_ph_mobile_v1(u.phone)=canonical
    AND NOT(u.id IS NOT DISTINCT FROM auth.uid() AND p_user_id IS NOT DISTINCT FROM auth.uid()));
END; $$;
REVOKE ALL ON FUNCTION public.canonical_profile_phone_v1() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.is_phone_available(text,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_phone_available(text,uuid) TO anon,authenticated;


-- 20261101000008_profile_writes.sql
-- Core profile writes acknowledge the persisted row. Auth owns email;
-- saved payment methods own receiving destinations. No history is rewritten.
CREATE OR REPLACE FUNCTION public.protect_profile_identity_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF NEW.email IS DISTINCT FROM (CASE WHEN TG_OP='UPDATE' THEN OLD.email ELSE NULL END)
     AND NEW.email IS DISTINCT FROM (SELECT email FROM auth.users WHERE id=NEW.id) THEN
    RAISE EXCEPTION 'Profile email must match Auth' USING ERRCODE='42501';
  END IF;
  IF current_setting('role',true) IN ('anon','authenticated') THEN
    IF TG_OP='INSERT' THEN
      IF coalesce(NEW.gcash_number,'')<>'' OR coalesce(NEW.maya_number,'')<>'' OR coalesce(NEW.qr_code_url,'')<>'' THEN
        RAISE EXCEPTION 'Use saved receiving methods' USING ERRCODE='42501';
      END IF;
    ELSIF NEW.gcash_number IS DISTINCT FROM OLD.gcash_number
       OR NEW.maya_number IS DISTINCT FROM OLD.maya_number
       OR NEW.qr_code_url IS DISTINCT FROM OLD.qr_code_url THEN
      RAISE EXCEPTION 'Use saved receiving methods' USING ERRCODE='42501';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS protect_profile_identity_v1 ON public.users;
CREATE TRIGGER protect_profile_identity_v1 BEFORE INSERT OR UPDATE ON public.users
FOR EACH ROW EXECUTE FUNCTION public.protect_profile_identity_v1();
REVOKE ALL ON FUNCTION public.protect_profile_identity_v1() FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.update_profile_v1(p_changes jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_actor uuid:=auth.uid(); v_row public.users%ROWTYPE; v_phone text; v_name text;
BEGIN
  IF v_actor IS NULL THEN RAISE EXCEPTION 'Sign in required' USING ERRCODE='42501'; END IF;
  IF p_changes IS NULL OR jsonb_typeof(p_changes)<>'object'
    OR p_changes - ARRAY['display_name','phone','avatar_url'] <> '{}'::jsonb THEN
    RAISE EXCEPTION 'Unsupported profile fields' USING ERRCODE='22023';
  END IF;
  SELECT * INTO v_row FROM public.users WHERE id=v_actor FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Profile unavailable' USING ERRCODE='P0002'; END IF;
  IF p_changes ? 'display_name' THEN
    v_name:=btrim(p_changes->>'display_name');
    IF jsonb_typeof(p_changes->'display_name')<>'string' OR v_name IS NULL OR length(v_name) NOT BETWEEN 1 AND 80 THEN
      RAISE EXCEPTION 'Invalid display name' USING ERRCODE='22023';
    END IF;
    v_row.display_name:=v_name;
  END IF;
  IF p_changes ? 'phone' THEN
    v_phone:=public.normalize_ph_mobile_v1(p_changes->>'phone');
    IF jsonb_typeof(p_changes->'phone')<>'string' OR v_phone IS NULL THEN
      RAISE EXCEPTION 'Invalid mobile number' USING ERRCODE='22023';
    END IF;
    v_row.phone:=v_phone;
  END IF;
  IF p_changes ? 'avatar_url' THEN
    IF jsonb_typeof(p_changes->'avatar_url')<>'string' OR length(p_changes->>'avatar_url')>2048 THEN
      RAISE EXCEPTION 'Invalid avatar' USING ERRCODE='22023';
    END IF;
    v_row.avatar_url:=p_changes->>'avatar_url';
  END IF;
  UPDATE public.users SET display_name=v_row.display_name, phone=v_row.phone,
    avatar_url=v_row.avatar_url, updated_at=now() WHERE id=v_actor RETURNING * INTO v_row;
  RETURN to_jsonb(v_row);
END;
$$;
REVOKE ALL ON FUNCTION public.update_profile_v1(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_profile_v1(jsonb) TO authenticated;
REVOKE UPDATE ON public.users FROM anon,authenticated;

-- Email confirmation or an OAuth metadata refresh must not restore old signup
-- name/phone/avatar over the user's subsequently saved profile edits.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  UPDATE public.users SET email=NEW.email,updated_at=now() WHERE id=NEW.id;
  IF FOUND THEN RETURN NEW; END IF;
  INSERT INTO public.users(id,email,phone,display_name,avatar_url)
  VALUES(NEW.id,NEW.email,coalesce(nullif(NEW.phone,''),NEW.raw_user_meta_data->>'phone'),
    coalesce(nullif(NEW.raw_user_meta_data->>'display_name',''),nullif(NEW.raw_user_meta_data->>'name',''),
      split_part(coalesce(NEW.email,'User'),'@',1)),NEW.raw_user_meta_data->>'avatar_url');
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC,anon,authenticated;


-- 20261101000009_profile_avatars.sql
-- Private, immutable profile images. Only the current reference is shared.
INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
VALUES('profile-avatars','profile-avatars',false,2097152,ARRAY['image/png'])
ON CONFLICT(id) DO UPDATE SET public=false,file_size_limit=2097152,allowed_mime_types=ARRAY['image/png'];

CREATE FUNCTION public.can_read_profile_avatar_v1(p_name text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
  SELECT auth.uid() IS NOT NULL AND (
    split_part(p_name,'/',1)=auth.uid()::text
    OR EXISTS(SELECT 1 FROM public.users u WHERE u.avatar_url='avatar:'||p_name AND (
      EXISTS(SELECT 1 FROM public.friendships f WHERE f.status='accepted' AND
        ((f.requester_id=auth.uid() AND f.addressee_id=u.id) OR
         (f.addressee_id=auth.uid() AND f.requester_id=u.id)))
      OR EXISTS(SELECT 1 FROM public.tabs t
        JOIN public.tab_members me ON me.tab_id=t.id AND me.user_id=auth.uid()
        JOIN public.tab_members peer ON peer.tab_id=t.id AND peer.user_id=u.id
        WHERE t.status='active' AND (t.group_id IS NULL OR
          (EXISTS(SELECT 1 FROM public.group_members gm WHERE gm.group_id=t.group_id AND gm.user_id=auth.uid() AND gm.status='active')
           AND EXISTS(SELECT 1 FROM public.group_members gm WHERE gm.group_id=t.group_id AND gm.user_id=u.id AND gm.status='active'))))
    ))
  );
$$;
REVOKE ALL ON FUNCTION public.can_read_profile_avatar_v1(text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_read_profile_avatar_v1(text) TO authenticated;
CREATE POLICY profile_avatar_read ON storage.objects FOR SELECT TO authenticated
USING(bucket_id='profile-avatars' AND public.can_read_profile_avatar_v1(name));
CREATE POLICY profile_avatar_insert ON storage.objects FOR INSERT TO authenticated
WITH CHECK(bucket_id='profile-avatars' AND name ~ ('^'||auth.uid()::text||'/[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.png$'));
-- No UPDATE or DELETE grants through a policy. Existing immutable objects are
-- retained for explicit cleanup/privacy work; removal only clears the profile.

CREATE FUNCTION public.validate_profile_avatar_v1() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  IF TG_OP='UPDATE' AND NEW.avatar_url IS NOT DISTINCT FROM OLD.avatar_url THEN RETURN NEW; END IF;
  IF coalesce(NEW.avatar_url,'') IN ('','asset:mascot','asset:cat_cool','asset:camera_snap') THEN RETURN NEW; END IF;
  -- Initial OAuth metadata can retain its legacy external reference. Clients
  -- render initials for external URLs; they never issue untrusted image HTTP.
  IF TG_OP='INSERT' AND NEW.avatar_url LIKE 'https://%' THEN RETURN NEW; END IF;
  IF NEW.avatar_url !~ ('^avatar:'||NEW.id::text||'/[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.png$')
    OR NOT EXISTS(SELECT 1 FROM storage.objects WHERE bucket_id='profile-avatars' AND name=substring(NEW.avatar_url from 8)) THEN
    RAISE EXCEPTION 'Upload an owned profile photo first' USING ERRCODE='22023';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER validate_profile_avatar BEFORE INSERT OR UPDATE OF avatar_url ON public.users
FOR EACH ROW EXECUTE FUNCTION public.validate_profile_avatar_v1();
REVOKE ALL ON FUNCTION public.validate_profile_avatar_v1() FROM PUBLIC,anon,authenticated;


-- 20261101000010_connection_preferences.sql
-- Private labels and reversible Connections views never edit shared money.
CREATE TABLE public.connection_preferences (
  owner_id uuid PRIMARY KEY REFERENCES public.users(id),
  revision bigint NOT NULL DEFAULT 0,
  nicknames jsonb NOT NULL DEFAULT '{}'::jsonb,
  archived_tab_ids uuid[] NOT NULL DEFAULT '{}'
);
CREATE TABLE public.connection_operations (
  owner_id uuid NOT NULL REFERENCES public.users(id), operation_id uuid NOT NULL,
  command jsonb NOT NULL, result jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(owner_id,operation_id)
);
ALTER TABLE public.connection_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.connection_operations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.connection_preferences,public.connection_operations FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.connection_preferences_v1() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE result jsonb;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in required' USING ERRCODE='42501'; END IF;
  SELECT jsonb_build_object('revision',revision,'nicknames',nicknames,'archived_tab_ids',to_jsonb(archived_tab_ids))
    INTO result FROM public.connection_preferences WHERE owner_id=auth.uid();
  RETURN coalesce(result,'{"revision":0,"nicknames":{},"archived_tab_ids":[]}'::jsonb);
END; $$;

CREATE FUNCTION public.change_connection_v1(p_operation_id uuid,p_command jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE actor uuid:=auth.uid(); previous public.connection_operations%ROWTYPE;
  prefs public.connection_preferences%ROWTYPE; target uuid; action text; nickname text; result jsonb;
BEGIN
  IF actor IS NULL THEN RAISE EXCEPTION 'Sign in required' USING ERRCODE='42501'; END IF;
  IF p_operation_id IS NULL OR p_command IS NULL OR jsonb_typeof(p_command)<>'object' THEN
    RAISE EXCEPTION 'Invalid connection command' USING ERRCODE='22023'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('connections:'||actor::text,0));
  SELECT * INTO previous FROM public.connection_operations WHERE owner_id=actor AND operation_id=p_operation_id;
  IF FOUND THEN
    IF previous.command<>p_command THEN RAISE EXCEPTION 'Operation payload changed' USING ERRCODE='22023'; END IF;
    RETURN previous.result;
  END IF;
  IF actor IS DISTINCT FROM (p_command->>'owner_id')::uuid THEN
    RAISE EXCEPTION 'Account changed' USING ERRCODE='42501'; END IF;
  IF p_command - ARRAY['owner_id','action','target_id','nickname','expected_revision']<>'{}'::jsonb
    OR jsonb_typeof(p_command->'expected_revision') IS DISTINCT FROM 'number'
    OR (p_command->>'expected_revision') !~ '^[0-9]+$' THEN
    RAISE EXCEPTION 'Invalid connection fields' USING ERRCODE='22023'; END IF;
  INSERT INTO public.connection_preferences(owner_id) VALUES(actor) ON CONFLICT DO NOTHING;
  SELECT * INTO prefs FROM public.connection_preferences WHERE owner_id=actor FOR UPDATE;
  IF prefs.revision<>(p_command->>'expected_revision')::bigint THEN
    RAISE EXCEPTION 'Connections changed. Reload and retry.' USING ERRCODE='40001'; END IF;
  action:=p_command->>'action'; target:=(p_command->>'target_id')::uuid;
  IF target IS NULL THEN RAISE EXCEPTION 'Missing target' USING ERRCODE='22023'; END IF;
  IF action='nickname' THEN
    IF target=actor OR NOT EXISTS(SELECT 1 FROM public.friendships f WHERE f.status='accepted'
      AND ((f.requester_id=actor AND f.addressee_id=target) OR (f.requester_id=target AND f.addressee_id=actor))) THEN
      RAISE EXCEPTION 'Accepted friend required' USING ERRCODE='42501'; END IF;
    nickname:=btrim(p_command->>'nickname');
    IF jsonb_typeof(p_command->'nickname') IS DISTINCT FROM 'string' OR length(nickname)>80 THEN
      RAISE EXCEPTION 'Invalid nickname' USING ERRCODE='22023'; END IF;
    IF nickname='' THEN prefs.nicknames:=prefs.nicknames-target::text;
    ELSE prefs.nicknames:=jsonb_set(prefs.nicknames,ARRAY[target::text],to_jsonb(nickname)); END IF;
  ELSIF action IN ('archive','restore') THEN
    IF NOT EXISTS(SELECT 1 FROM public.tabs t JOIN public.tab_members tm ON tm.tab_id=t.id AND tm.user_id=actor
       WHERE t.id=target AND t.tab_type='group' AND t.status='active'
         AND (t.group_id IS NULL OR EXISTS(SELECT 1 FROM public.group_members gm
           WHERE gm.group_id=t.group_id AND gm.user_id=actor AND gm.status='active'))) THEN
      RAISE EXCEPTION 'Active group member required' USING ERRCODE='42501'; END IF;
    prefs.archived_tab_ids:=array_remove(prefs.archived_tab_ids,target);
    IF action='archive' THEN prefs.archived_tab_ids:=array_append(prefs.archived_tab_ids,target); END IF;
  ELSIF action='unfriend' THEN
    IF target=actor THEN RAISE EXCEPTION 'Invalid friend' USING ERRCODE='22023'; END IF;
    DELETE FROM public.friendships f WHERE f.status='accepted'
      AND ((f.requester_id=actor AND f.addressee_id=target) OR (f.requester_id=target AND f.addressee_id=actor));
  ELSE RAISE EXCEPTION 'Unsupported action' USING ERRCODE='22023';
  END IF;
  UPDATE public.connection_preferences SET nicknames=prefs.nicknames,
    archived_tab_ids=prefs.archived_tab_ids,revision=revision+1 WHERE owner_id=actor;
  result:=public.connection_preferences_v1();
  INSERT INTO public.connection_operations(owner_id,operation_id,command,result) VALUES(actor,p_operation_id,p_command,result);
  RETURN result;
END; $$;
REVOKE ALL ON FUNCTION public.connection_preferences_v1(),public.change_connection_v1(uuid,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.connection_preferences_v1(),public.change_connection_v1(uuid,jsonb) TO authenticated;

CREATE FUNCTION public.protect_shared_archive_v1() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status AND (NEW.status='archived' OR OLD.status='archived')
     AND current_setting('role',true) IN ('anon','authenticated') THEN
    RAISE EXCEPTION 'Use private Connections archive' USING ERRCODE='42501'; END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER protect_shared_archive BEFORE UPDATE OF status ON public.tabs
FOR EACH ROW EXECUTE FUNCTION public.protect_shared_archive_v1();
REVOKE ALL ON FUNCTION public.protect_shared_archive_v1() FROM PUBLIC,anon,authenticated;

-- Bind core profile/social writes to the initiating actor even if a client's
-- bearer token changes while an asynchronous HTTP request is being prepared.
CREATE FUNCTION public.update_profile_v2(p_expected_owner uuid,p_changes jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  IF auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM p_expected_owner THEN
    RAISE EXCEPTION 'Account changed' USING ERRCODE='42501'; END IF;
  RETURN public.update_profile_v1(p_changes);
END; $$;
REVOKE ALL ON FUNCTION public.update_profile_v1(jsonb),public.update_profile_v2(uuid,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.update_profile_v2(uuid,jsonb) TO authenticated;

CREATE FUNCTION public.remove_friend_v2(p_expected_owner uuid,p_friend_user_id uuid) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  IF auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM p_expected_owner THEN
    RAISE EXCEPTION 'Account changed' USING ERRCODE='42501'; END IF;
  IF p_friend_user_id IS NULL OR p_friend_user_id=auth.uid() THEN RETURN false; END IF;
  DELETE FROM public.friendships f WHERE f.status='accepted' AND
    ((f.requester_id=auth.uid() AND f.addressee_id=p_friend_user_id) OR
     (f.requester_id=p_friend_user_id AND f.addressee_id=auth.uid()));
  RETURN true;
END; $$;
REVOKE ALL ON FUNCTION public.remove_friend_v2(uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.remove_friend_v2(uuid,uuid) TO authenticated;
DO $$ BEGIN
  IF to_regprocedure('public.remove_friend(uuid)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.remove_friend(uuid) FROM PUBLIC,anon,authenticated;
  END IF;
END $$;

-- Intentionally limited personal-data export. Shared ledger/media need a
-- separate paginated export contract; do not expose arbitrary row JSON.
BEGIN;
CREATE OR REPLACE FUNCTION public.export_account_data_v1()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public AS $$
DECLARE actor uuid := auth.uid(); result jsonb;
BEGIN
  IF actor IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;
  SELECT jsonb_build_object(
    'version', 1, 'account_id', actor, 'generated_at', statement_timestamp(),
    'scope', 'profile_and_owned_contacts',
    'excluded', jsonb_build_array('shared_ledger', 'payment_methods',
      'media', 'notifications', 'authentication_records', 'local_drafts'),
    'profile', (SELECT jsonb_build_object(
      'id', u.id, 'display_name', u.display_name, 'email', u.email,
      'phone', u.phone, 'created_at', u.created_at)
      FROM public.users u WHERE u.id = actor),
    'contacts', COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id', c.id, 'display_name', c.display_name, 'email', c.email,
      'phone', c.phone, 'created_at', c.created_at) ORDER BY c.id)
      FROM public.contacts c WHERE c.owner_user_id = actor), '[]'::jsonb)
  ) INTO result;
  RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.export_account_data_v1() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.export_account_data_v1() TO authenticated;
COMMIT;

BEGIN;
CREATE TABLE public.account_deletion_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL UNIQUE REFERENCES public.users(id) ON DELETE RESTRICT,
  requested_at timestamptz NOT NULL DEFAULT now(),
  status text NOT NULL DEFAULT 'requested' CHECK (status IN ('requested', 'processing', 'completed'))
);
ALTER TABLE public.account_deletion_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.account_deletion_requests FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.account_deletion_requests TO authenticated;
CREATE POLICY read_own_deletion_request ON public.account_deletion_requests
  FOR SELECT TO authenticated USING (user_id = auth.uid());

CREATE OR REPLACE FUNCTION public.request_account_deletion_v1()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public AS $$
DECLARE actor uuid := auth.uid(); request public.account_deletion_requests;
BEGIN
  IF actor IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;
  -- AMR timestamps describe actual authentication, unlike refreshed-token iat.
  -- Claims come from the verified JWT at the PostgREST boundary.
  IF NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(COALESCE(auth.jwt()->'amr', '[]'::jsonb)) m
    WHERE m->>'method' IN ('password', 'otp', 'oauth', 'totp', 'sso/saml')
      AND CASE WHEN m->>'timestamp' ~ '^[0-9]{1,12}$'
        THEN (m->>'timestamp')::bigint
          BETWEEN extract(epoch FROM statement_timestamp())::bigint - 300
          AND extract(epoch FROM statement_timestamp())::bigint + 30
        ELSE false END
  ) THEN
    RAISE EXCEPTION 'Sign in again before requesting account deletion' USING ERRCODE = '42501';
  END IF;
  INSERT INTO public.account_deletion_requests(user_id) VALUES (actor)
    ON CONFLICT (user_id) DO NOTHING;
  SELECT * INTO STRICT request FROM public.account_deletion_requests WHERE user_id = actor;
  RETURN jsonb_build_object('id', request.id, 'account_id', actor,
    'requested_at', request.requested_at, 'status', request.status);
END $$;
REVOKE ALL ON FUNCTION public.request_account_deletion_v1() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_account_deletion_v1() TO authenticated;
-- This migration records a request only. It never deletes accounts, media or
-- financial history. A reviewed anonymization/retention processor is required.
COMMIT;

BEGIN;
-- No target-account argument: the server chooses scope from the JWT subject.
-- Explicit projections avoid exporting storage URLs or newly added columns.
CREATE OR REPLACE FUNCTION public.export_ledger_page_v1(
  p_section text, p_after uuid DEFAULT NULL, p_limit integer DEFAULT 50
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public AS $$
DECLARE actor uuid := auth.uid(); rows jsonb; last_id uuid; has_more boolean;
BEGIN
  IF actor IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;
  IF p_section IS NULL OR p_section NOT IN ('tabs', 'expenses', 'shares', 'payments')
    OR p_limit IS NULL OR p_limit < 1 OR p_limit > 100 THEN
    RAISE EXCEPTION 'Invalid export section or page size' USING ERRCODE = '22023';
  END IF;
  WITH authorized_tabs AS (
    SELECT t.id FROM public.tabs t
    WHERE t.user_a = actor OR t.user_b = actor OR EXISTS (
      SELECT 1 FROM public.tab_members m WHERE m.tab_id = t.id AND m.user_id = actor)
  ), scoped AS (
    SELECT t.id, jsonb_build_object('id',t.id, 'type',t.tab_type,
      'status',t.status, 'group_id',t.group_id, 'user_a',t.user_a,
      'user_b',t.user_b, 'created_at',t.created_at) AS record
    FROM public.tabs t JOIN authorized_tabs a ON a.id = t.id
    WHERE p_section = 'tabs'
    UNION ALL
    SELECT t.id, jsonb_build_object('id',t.id, 'tab_id',t.tab_id,
      'created_by',t.created_by, 'description',t.description,
      'category',t.category, 'status',t.status, 'total_amount_centavos',t.total_amount_centavos,
      'currency',t.currency, 'transaction_date',t.transaction_date,
      'due_date',t.due_date, 'created_at',t.created_at)
    FROM public.transactions t JOIN authorized_tabs a ON a.id = t.tab_id
    WHERE p_section = 'expenses'
    UNION ALL
    SELECT s.id, jsonb_build_object('id',s.id, 'transaction_id',s.transaction_id,
      'user_id',s.user_id, 'contact_id',s.contact_id,
      'role',s.participant_role, 'share_amount_centavos',s.share_amount_centavos,
      'acknowledged',s.acknowledged, 'acknowledged_at',s.acknowledged_at)
    FROM public.transaction_participants s
    JOIN public.transactions t ON t.id = s.transaction_id
    JOIN authorized_tabs a ON a.id = t.tab_id
    WHERE p_section = 'shares'
    UNION ALL
    SELECT p.id, jsonb_build_object('id',p.id, 'tab_id',p.tab_id,
      'submitted_by',p.submitted_by, 'recipient_user_id',p.recipient_user_id,
      'amount_centavos',p.amount_centavos, 'payment_method',p.payment_method,
      'note',p.note, 'status',p.status, 'submitted_at',p.submitted_at,
      'confirmed_by',p.confirmed_by, 'confirmed_at',p.confirmed_at)
    FROM public.payments p JOIN authorized_tabs a ON a.id = p.tab_id
    WHERE p_section = 'payments'
  ), page_window AS (
    SELECT * FROM scoped WHERE p_after IS NULL OR id > p_after
    ORDER BY id LIMIT p_limit + 1
  ), page AS (
    SELECT * FROM page_window ORDER BY id LIMIT p_limit
  )
  SELECT COALESCE((SELECT jsonb_agg(record ORDER BY id) FROM page),'[]'::jsonb),
    (SELECT id FROM page ORDER BY id DESC LIMIT 1),
    (SELECT count(*) > p_limit FROM page_window)
  INTO rows, last_id, has_more;
  RETURN jsonb_build_object('version',1, 'account_id',actor,
    'section',p_section, 'records',rows,
    'next_cursor',CASE WHEN has_more THEN last_id ELSE NULL END,
    'generated_at',statement_timestamp(),
    'consistency','Each page is a current read, not a whole-export snapshot.');
END $$;
REVOKE ALL ON FUNCTION public.export_ledger_page_v1(text,uuid,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.export_ledger_page_v1(text,uuid,integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_account_deletion_request_v1()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public AS $$
DECLARE actor uuid := auth.uid(); result jsonb;
BEGIN
  IF actor IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;
  SELECT jsonb_build_object('id',r.id,'account_id',actor,
    'requested_at',r.requested_at,'status',r.status)
  INTO result FROM public.account_deletion_requests r WHERE r.user_id = actor;
  RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_account_deletion_request_v1() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_account_deletion_request_v1() TO authenticated;
COMMIT;

BEGIN;
CREATE TABLE public.expense_change_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  transaction_id uuid NOT NULL REFERENCES public.transactions(id) ON DELETE RESTRICT,
  requested_by uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  reviewer_id uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  kind text NOT NULL CHECK (kind IN ('correct','cancel')),
  new_total_centavos bigint,
  reason text NOT NULL CHECK (length(trim(reason)) BETWEEN 1 AND 500),
  original_snapshot jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (requested_by <> reviewer_id),
  CHECK ((kind='cancel' AND new_total_centavos IS NULL) OR
    (kind='correct' AND new_total_centavos BETWEEN 1 AND 99999999999))
);
CREATE INDEX ON public.expense_change_requests(transaction_id,created_at,id);
CREATE TABLE public.expense_change_decisions (
  change_id uuid PRIMARY KEY REFERENCES public.expense_change_requests(id) ON DELETE RESTRICT,
  actor_id uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  accepted boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.expense_change_results (
  change_id uuid PRIMARY KEY REFERENCES public.expense_change_requests(id) ON DELETE RESTRICT,
  transaction_id uuid NOT NULL UNIQUE REFERENCES public.transactions(id) ON DELETE RESTRICT,
  reversal_id uuid REFERENCES public.transactions(id) ON DELETE RESTRICT,
  replacement_id uuid REFERENCES public.transactions(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.expense_change_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expense_change_decisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expense_change_results ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.expense_change_requests,public.expense_change_decisions,
  public.expense_change_results FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.request_expense_change_v1(
  p_operation_id uuid,p_transaction_id uuid,p_kind text,p_new_total bigint,p_reason text,p_expected_actor uuid
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor uuid:=auth.uid(); expense public.transactions;
  roster integer; reviewer uuid; result uuid; previous public.financial_operations;
  command jsonb:=jsonb_build_object('transaction_id',p_transaction_id,'kind',p_kind,
    'new_total',p_new_total,'reason',p_reason);
BEGIN
  IF actor IS NULL OR actor IS DISTINCT FROM p_expected_actor THEN RAISE EXCEPTION 'Initiating account required' USING ERRCODE='42501'; END IF;
  IF p_operation_id IS NULL OR p_kind IS NULL OR p_kind NOT IN ('correct','cancel')
    OR p_reason IS NULL OR length(trim(p_reason)) NOT BETWEEN 1 AND 500 THEN
    RAISE EXCEPTION 'Change identity, kind and reason required' USING ERRCODE='22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':'||p_operation_id::text,0));
  SELECT * INTO previous FROM public.financial_operations WHERE actor_id=actor AND operation_id=p_operation_id;
  IF FOUND THEN
    IF previous.command_kind<>'expense_change' OR previous.command IS DISTINCT FROM command THEN
      RAISE EXCEPTION 'Operation ID reused with a different command' USING ERRCODE='22023';
    END IF;
    RETURN previous.result_id;
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(p_transaction_id::text,1));
  SELECT * INTO expense FROM public.transactions WHERE id=p_transaction_id;
  IF NOT FOUND OR NOT public.is_tab_member(expense.tab_id,actor) OR NOT EXISTS (
    SELECT 1 FROM public.transaction_participants WHERE transaction_id=expense.id AND user_id=actor)
    OR NOT EXISTS(SELECT 1 FROM public.tabs WHERE id=expense.tab_id AND tab_type='individual') THEN
    RAISE EXCEPTION 'Expense participant required' USING ERRCODE='42501';
  END IF;
  SELECT count(*), min(user_id::text) FILTER (WHERE user_id<>actor)::uuid
    INTO roster,reviewer FROM public.transaction_participants WHERE transaction_id=expense.id;
  IF roster<>2 OR reviewer IS NULL OR EXISTS(SELECT 1 FROM public.transaction_participants
    WHERE transaction_id=expense.id AND (contact_id IS NOT NULL OR user_id IS NULL))
    OR (SELECT count(*) FROM public.transaction_participants WHERE transaction_id=expense.id AND participant_role='payer')<>1
    OR (SELECT sum(share_amount_centavos) FROM public.transaction_participants WHERE transaction_id=expense.id)<>expense.total_amount_centavos
    OR expense.status NOT IN ('pending','acknowledged')
    OR expense.total_amount_centavos>99999999999
    OR EXISTS(SELECT 1 FROM public.expense_change_results WHERE reversal_id=expense.id) THEN
    RAISE EXCEPTION 'This expense cannot be changed by this workflow' USING ERRCODE='22023';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.tabs WHERE id=expense.tab_id
    AND LEAST(user_a,user_b)=LEAST(actor,reviewer) AND GREATEST(user_a,user_b)=GREATEST(actor,reviewer)
    AND user_a IS NOT NULL AND user_b IS NOT NULL) THEN
    RAISE EXCEPTION 'Expense must match the registered bilateral pair' USING ERRCODE='22023';
  END IF;
  IF (p_kind='cancel' AND p_new_total IS NOT NULL) OR
    (p_kind='correct' AND (p_new_total IS NULL OR p_new_total NOT BETWEEN 1 AND 99999999999
      OR p_new_total=expense.total_amount_centavos)) THEN
    RAISE EXCEPTION 'A different positive total or cancellation is required' USING ERRCODE='22023';
  END IF;
  IF EXISTS(SELECT 1 FROM public.expense_change_results WHERE transaction_id=expense.id) THEN
    RAISE EXCEPTION 'Expense already revised; use its replacement' USING ERRCODE='22023';
  END IF;
  INSERT INTO public.expense_change_requests(transaction_id,requested_by,reviewer_id,kind,new_total_centavos,reason,original_snapshot)
    VALUES(expense.id,actor,reviewer,p_kind,p_new_total,trim(p_reason),
      jsonb_build_object('expense',to_jsonb(expense),'shares',
        (SELECT jsonb_agg(to_jsonb(s) ORDER BY s.id) FROM public.transaction_participants s WHERE transaction_id=expense.id))) RETURNING id INTO result;
  INSERT INTO public.notifications(recipient_user_id,notification_type,related_tab_id,related_transaction_id,title,body)
    VALUES(reviewer,'amount_proposed',expense.tab_id,expense.id,'Expense change requested','Review a proposed change in your shared tab.');
  INSERT INTO public.financial_operations(actor_id,operation_id,command_kind,command,result_id)
    VALUES(actor,p_operation_id,'expense_change',command,result);
  RETURN result;
END $$;

CREATE FUNCTION public.decide_expense_change_v1(p_change_id uuid,p_accept boolean,p_expected_actor uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor uuid:=auth.uid(); change public.expense_change_requests;
  old_decision public.expense_change_decisions; expense public.transactions;
  payer public.transaction_participants; debtor public.transaction_participants;
  reversed uuid; replacement uuid; new_share bigint;
BEGIN
  SELECT * INTO change FROM public.expense_change_requests WHERE id=p_change_id;
  IF actor IS NULL OR actor IS DISTINCT FROM p_expected_actor OR change.id IS NULL OR actor IS DISTINCT FROM change.reviewer_id
    OR NOT public.is_tab_member((SELECT tab_id FROM public.transactions WHERE id=change.transaction_id),actor) THEN
    RAISE EXCEPTION 'Other expense participant must review' USING ERRCODE='42501';
  END IF;
  IF p_accept IS NULL THEN RAISE EXCEPTION 'Decision required' USING ERRCODE='22023'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(change.transaction_id::text,1));
  SELECT * INTO old_decision FROM public.expense_change_decisions WHERE change_id=change.id;
  IF FOUND THEN
    IF old_decision.accepted IS DISTINCT FROM p_accept THEN
      RAISE EXCEPTION 'Decision already recorded' USING ERRCODE='22023';
    END IF;
    RETURN change.id;
  END IF;
  IF EXISTS(SELECT 1 FROM public.expense_change_results WHERE transaction_id=change.transaction_id) THEN
    RAISE EXCEPTION 'Another revision was applied' USING ERRCODE='22023';
  END IF;
  SELECT * INTO expense FROM public.transactions WHERE id=change.transaction_id FOR SHARE;
  PERFORM 1 FROM public.transaction_participants WHERE transaction_id=expense.id FOR SHARE;
  IF change.original_snapshot IS DISTINCT FROM jsonb_build_object('expense',to_jsonb(expense),'shares',
    (SELECT jsonb_agg(to_jsonb(s) ORDER BY s.id) FROM public.transaction_participants s WHERE transaction_id=expense.id)) THEN
    RAISE EXCEPTION 'Original expense changed; request a fresh review' USING ERRCODE='22023';
  END IF;
  INSERT INTO public.expense_change_decisions(change_id,actor_id,accepted) VALUES(change.id,actor,p_accept);
  IF NOT p_accept THEN RETURN change.id; END IF;
  -- Use the same tab lock as settlement/receipt commands while appending money.
  PERFORM pg_advisory_xact_lock(hashtextextended(expense.tab_id::text,0));
  SELECT * INTO STRICT payer FROM public.transaction_participants WHERE transaction_id=expense.id AND participant_role='payer';
  SELECT * INTO STRICT debtor FROM public.transaction_participants WHERE transaction_id=expense.id AND id<>payer.id;
  IF debtor.share_amount_centavos>0 THEN
    reversed:=public.create_expense_atomic(expense.tab_id,
      'Reversal: '||expense.description,expense.category,debtor.share_amount_centavos,debtor.user_id,
      jsonb_build_array(
        jsonb_build_object('user_id',debtor.user_id,'participant_role','payer','share_amount_centavos',0),
        jsonb_build_object('user_id',payer.user_id,'participant_role','debtor','share_amount_centavos',debtor.share_amount_centavos)),
      NULL,NULL);
  END IF;
  IF change.kind='correct' THEN
    new_share:=trunc(change.new_total_centavos::numeric*debtor.share_amount_centavos/expense.total_amount_centavos)::bigint;
    replacement:=public.create_expense_atomic(expense.tab_id,
      expense.description,expense.category,change.new_total_centavos,payer.user_id,
      jsonb_build_array(
        jsonb_build_object('user_id',payer.user_id,'participant_role','payer','share_amount_centavos',change.new_total_centavos-new_share),
        jsonb_build_object('user_id',debtor.user_id,'participant_role',debtor.participant_role,'share_amount_centavos',new_share)),
      expense.due_date,expense.receipt_url);
  END IF;
  INSERT INTO public.expense_change_results(change_id,transaction_id,reversal_id,replacement_id)
    VALUES(change.id,expense.id,reversed,replacement);
  INSERT INTO public.activity_logs(actor_user_id,tab_id,transaction_id,event_type,metadata)
    VALUES(actor,expense.tab_id,expense.id,'EXPENSE_CHANGE_APPLIED',jsonb_build_object(
      'change_id',change.id,'kind',change.kind,'reason',change.reason,'reversal_id',reversed,'replacement_id',replacement));
  INSERT INTO public.notifications(recipient_user_id,notification_type,related_tab_id,related_transaction_id,title,body)
    VALUES(change.requested_by,'amount_changed',expense.tab_id,expense.id,'Expense change accepted','Your shared history now includes the agreed revision.');
  RETURN change.id;
END $$;

CREATE FUNCTION public.list_expense_changes_v1(p_transaction_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor uuid:=auth.uid(); result jsonb;
BEGIN
  IF actor IS NULL OR NOT EXISTS(SELECT 1 FROM public.transaction_participants s
    JOIN public.transactions t ON t.id=s.transaction_id WHERE s.transaction_id=p_transaction_id
      AND s.user_id=actor AND public.is_tab_member(t.tab_id,actor)) THEN
    RAISE EXCEPTION 'Expense participant required' USING ERRCODE='42501';
  END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id',r.id,'transaction_id',r.transaction_id,
    'requested_by',r.requested_by,'reviewer_id',r.reviewer_id,'kind',r.kind,
    'new_total_centavos',r.new_total_centavos,'reason',r.reason,'created_at',r.created_at,
    'status',CASE WHEN o.change_id IS NOT NULL THEN 'applied' WHEN d.accepted=false THEN 'rejected'
      WHEN EXISTS(SELECT 1 FROM public.expense_change_results x WHERE x.transaction_id=r.transaction_id) THEN 'superseded'
      ELSE 'pending' END,'reversal_id',o.reversal_id,'replacement_id',o.replacement_id)
    ORDER BY r.created_at,r.id),'[]'::jsonb) INTO result
  FROM public.expense_change_requests r LEFT JOIN public.expense_change_decisions d ON d.change_id=r.id
    LEFT JOIN public.expense_change_results o ON o.change_id=r.id WHERE r.transaction_id=p_transaction_id;
  RETURN jsonb_build_object('account_id',actor,'transaction_id',p_transaction_id,'changes',result,
    'can_request',NOT EXISTS(SELECT 1 FROM public.expense_change_results
      WHERE reversal_id=p_transaction_id OR transaction_id=p_transaction_id)
      AND EXISTS(SELECT 1 FROM public.transactions t JOIN public.tabs tab ON tab.id=t.tab_id
        WHERE t.id=p_transaction_id AND tab.tab_type='individual' AND t.status IN ('pending','acknowledged')
          AND t.total_amount_centavos BETWEEN 1 AND 99999999999
          AND tab.user_a IS NOT NULL AND tab.user_b IS NOT NULL
          AND (SELECT count(*) FROM public.transaction_participants s WHERE s.transaction_id=t.id AND s.user_id IN (tab.user_a,tab.user_b))=2)
      AND (SELECT count(*) FROM public.transaction_participants WHERE transaction_id=p_transaction_id)=2
      AND NOT EXISTS(SELECT 1 FROM public.transaction_participants WHERE transaction_id=p_transaction_id AND (contact_id IS NOT NULL OR user_id IS NULL))
      AND (SELECT count(*) FROM public.transaction_participants WHERE transaction_id=p_transaction_id AND participant_role='payer')=1);
END $$;
REVOKE ALL ON FUNCTION public.request_expense_change_v1(uuid,uuid,text,bigint,text,uuid),
  public.decide_expense_change_v1(uuid,boolean,uuid),public.list_expense_changes_v1(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.request_expense_change_v1(uuid,uuid,text,bigint,text,uuid),
  public.decide_expense_change_v1(uuid,boolean,uuid),public.list_expense_changes_v1(uuid) TO authenticated;
COMMIT;


BEGIN;
CREATE TABLE public.expense_change_outputs (
  transaction_id uuid PRIMARY KEY REFERENCES public.transactions(id) ON DELETE RESTRICT,
  change_id uuid NOT NULL REFERENCES public.expense_change_results(change_id) ON DELETE RESTRICT,
  role text NOT NULL CHECK(role IN ('reversal','replacement'))
);
CREATE INDEX ON public.expense_change_outputs(change_id);
ALTER TABLE public.expense_change_outputs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.expense_change_outputs FROM PUBLIC,anon,authenticated;
INSERT INTO public.expense_change_outputs(transaction_id,change_id,role)
  SELECT reversal_id,change_id,'reversal' FROM public.expense_change_results WHERE reversal_id IS NOT NULL
  UNION ALL SELECT replacement_id,change_id,'replacement' FROM public.expense_change_results WHERE replacement_id IS NOT NULL;

CREATE FUNCTION public.record_expense_change_outputs() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  IF NEW.reversal_id IS NOT NULL THEN
    INSERT INTO public.expense_change_outputs VALUES(NEW.reversal_id,NEW.change_id,'reversal');
  END IF;
  IF NEW.replacement_id IS NOT NULL THEN
    INSERT INTO public.expense_change_outputs VALUES(NEW.replacement_id,NEW.change_id,'replacement');
  END IF;
  UPDATE public.reminders SET status='cancelled' WHERE transaction_id=NEW.transaction_id AND status='scheduled';
  UPDATE public.push_delivery_jobs j SET status='cancelled',lease_id=NULL,lease_until=NULL
    FROM public.notifications n WHERE j.notification_id=n.id AND n.related_transaction_id=NEW.transaction_id
      AND j.status IN ('pending','sending');
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.record_expense_change_outputs() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER record_expense_change_outputs AFTER INSERT ON public.expense_change_results
  FOR EACH ROW EXECUTE FUNCTION public.record_expense_change_outputs();

-- PostgREST computed field. The unnamed row parameter is not an RPC argument.
-- Only its ID is used; authorization is checked against stored rows.
CREATE FUNCTION public.expense_revision(public.transactions) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor uuid:=auth.uid(); result jsonb; parent jsonb;
BEGIN
  IF actor IS NULL OR NOT EXISTS(SELECT 1 FROM public.transactions t
    JOIN public.transaction_participants s ON s.transaction_id=t.id
    WHERE t.id=($1).id AND s.user_id=actor AND public.is_tab_member(t.tab_id,actor)) THEN RETURN NULL; END IF;
  SELECT value INTO result FROM (
    SELECT 0 priority,jsonb_build_object('change_id',r.id,'original_id',r.transaction_id,
      'role','original','kind',r.kind,'reason',r.reason) value
      FROM public.expense_change_results z JOIN public.expense_change_requests r ON r.id=z.change_id
      WHERE z.transaction_id=($1).id
    UNION ALL
    SELECT 1,jsonb_build_object('change_id',r.id,'original_id',r.transaction_id,
      'role',o.role,'kind',r.kind,'reason',r.reason)
      FROM public.expense_change_outputs o JOIN public.expense_change_requests r ON r.id=o.change_id
      WHERE o.transaction_id=($1).id
  ) refs ORDER BY priority LIMIT 1;
  SELECT jsonb_build_object('parent_change_id',r.id,'parent_original_id',r.transaction_id)
    INTO parent FROM public.expense_change_outputs o JOIN public.expense_change_requests r ON r.id=o.change_id
    WHERE o.transaction_id=($1).id;
  IF parent IS NOT NULL THEN result:=result||parent; END IF;
  RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.expense_revision(public.transactions) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.expense_revision(public.transactions) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;

BEGIN;
ALTER TABLE public.expense_change_requests ALTER COLUMN reviewer_id DROP NOT NULL;
ALTER TABLE public.expense_change_requests ADD COLUMN manual_contact_agreement boolean NOT NULL DEFAULT false;
ALTER TABLE public.expense_change_decisions DROP CONSTRAINT expense_change_decisions_pkey;
ALTER TABLE public.expense_change_decisions ADD PRIMARY KEY(change_id,actor_id);
CREATE TABLE public.expense_change_reviewers (
  change_id uuid NOT NULL REFERENCES public.expense_change_requests(id) ON DELETE RESTRICT,
  reviewer_id uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  PRIMARY KEY(change_id,reviewer_id)
);
ALTER TABLE public.expense_change_reviewers ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.expense_change_reviewers FROM PUBLIC,anon,authenticated;
INSERT INTO public.expense_change_reviewers SELECT id,reviewer_id FROM public.expense_change_requests WHERE reviewer_id IS NOT NULL;

CREATE FUNCTION public.expense_change_context_internal(p_id uuid,p_actor uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE expense public.transactions; tab public.tabs; n integer; contacts integer; payers integer; total numeric;
BEGIN
  SELECT * INTO expense FROM public.transactions WHERE id=p_id;
  IF expense.id IS NULL OR NOT public.is_tab_member(expense.tab_id,p_actor) OR NOT EXISTS(
    SELECT 1 FROM public.transaction_participants WHERE transaction_id=p_id AND user_id=p_actor) THEN RETURN NULL; END IF;
  SELECT * INTO tab FROM public.tabs WHERE id=expense.tab_id;
  SELECT count(*),count(*) FILTER(WHERE contact_id IS NOT NULL),
    count(*) FILTER(WHERE participant_role='payer'),sum(share_amount_centavos)
    INTO n,contacts,payers,total FROM public.transaction_participants WHERE transaction_id=p_id;
  IF n NOT BETWEEN 1 AND 100 OR payers<>1 OR total<>expense.total_amount_centavos
    OR expense.total_amount_centavos NOT BETWEEN 1 AND 99999999999
    OR expense.status NOT IN ('pending','acknowledged')
    OR EXISTS(SELECT 1 FROM public.transaction_participants WHERE transaction_id=p_id
      AND ((user_id IS NULL)=(contact_id IS NULL) OR (user_id IS NOT NULL AND NOT public.is_tab_member(expense.tab_id,user_id))))
    OR EXISTS(SELECT 1 FROM public.expense_change_outputs WHERE transaction_id=p_id AND role='reversal') THEN RETURN NULL; END IF;
  IF contacts>0 THEN
    IF tab.tab_type<>'individual' OR contacts<>1 OR n<>2 OR NOT EXISTS(
      SELECT 1 FROM public.transaction_participants s JOIN public.contacts c ON c.id=s.contact_id
      WHERE s.transaction_id=p_id AND c.owner_user_id=p_actor AND c.claimed_user_id IS NULL) THEN RETURN NULL; END IF;
  ELSIF tab.tab_type IN ('individual','shared_couple') THEN
    IF n<>2 OR tab.user_a IS NULL OR tab.user_b IS NULL OR
      (SELECT count(*) FROM public.transaction_participants WHERE transaction_id=p_id AND user_id IN(tab.user_a,tab.user_b))<>2 THEN RETURN NULL; END IF;
  ELSIF tab.tab_type<>'group' THEN RETURN NULL;
  END IF;
  RETURN jsonb_build_object('can_request',NOT EXISTS(SELECT 1 FROM public.expense_change_results WHERE transaction_id=p_id),
    'manual_contact',contacts=1);
END $$;
REVOKE ALL ON FUNCTION public.expense_change_context_internal(uuid,uuid) FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.apply_expense_change_internal(p_change_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE change public.expense_change_requests; expense public.transactions;
  payer public.transaction_participants; party public.transaction_participants;
  reversed uuid; first_reversal uuid; replacement uuid; reversals uuid[]:='{}';
  shares jsonb:='[]'; payer_share bigint; new_share bigint;
BEGIN
  SELECT * INTO STRICT change FROM public.expense_change_requests WHERE id=p_change_id;
  PERFORM pg_advisory_xact_lock(hashtextextended(change.transaction_id::text,1));
  IF EXISTS(SELECT 1 FROM public.expense_change_results WHERE transaction_id=change.transaction_id) THEN
    RAISE EXCEPTION 'Expense already revised' USING ERRCODE='22023'; END IF;
  IF EXISTS(SELECT 1 FROM public.expense_change_reviewers r WHERE r.change_id=p_change_id AND NOT EXISTS(
    SELECT 1 FROM public.expense_change_decisions d WHERE d.change_id=r.change_id AND d.actor_id=r.reviewer_id AND d.accepted))
    OR EXISTS(SELECT 1 FROM public.expense_change_decisions WHERE change_id=p_change_id AND NOT accepted) THEN
    RAISE EXCEPTION 'All registered participants must agree' USING ERRCODE='42501'; END IF;
  SELECT * INTO expense FROM public.transactions WHERE id=change.transaction_id FOR SHARE;
  PERFORM 1 FROM public.transaction_participants WHERE transaction_id=expense.id FOR SHARE;
  IF change.original_snapshot IS DISTINCT FROM jsonb_build_object('expense',to_jsonb(expense),'shares',
    (SELECT jsonb_agg(to_jsonb(s) ORDER BY s.id) FROM public.transaction_participants s WHERE transaction_id=expense.id)) THEN
    RAISE EXCEPTION 'Original expense changed; request a fresh review' USING ERRCODE='22023'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(expense.tab_id::text,0));
  SELECT * INTO STRICT payer FROM public.transaction_participants WHERE transaction_id=expense.id AND participant_role='payer';
  payer_share:=change.new_total_centavos;
  FOR party IN SELECT * FROM public.transaction_participants WHERE transaction_id=expense.id AND id<>payer.id ORDER BY id LOOP
    IF party.share_amount_centavos>0 THEN
      reversed:=public.create_expense_atomic(expense.tab_id,'Reversal: '||expense.description,expense.category,
        party.share_amount_centavos,COALESCE(party.user_id,party.contact_id),jsonb_build_array(
          jsonb_build_object('user_id',party.user_id,'contact_id',party.contact_id,'participant_role','payer','share_amount_centavos',0),
          jsonb_build_object('user_id',payer.user_id,'contact_id',payer.contact_id,'participant_role','debtor','share_amount_centavos',party.share_amount_centavos)),NULL,NULL);
      reversals:=array_append(reversals,reversed);
      IF first_reversal IS NULL THEN first_reversal:=reversed; END IF;
    END IF;
    IF change.kind='correct' THEN
      new_share:=trunc(change.new_total_centavos::numeric*party.share_amount_centavos/expense.total_amount_centavos)::bigint;
      payer_share:=payer_share-new_share;
      shares:=shares||jsonb_build_array(jsonb_build_object('user_id',party.user_id,'contact_id',party.contact_id,
        'participant_role',party.participant_role,'share_amount_centavos',new_share));
    END IF;
  END LOOP;
  IF change.kind='correct' THEN
    shares:=shares||jsonb_build_array(jsonb_build_object('user_id',payer.user_id,'contact_id',payer.contact_id,'participant_role','payer','share_amount_centavos',payer_share));
    replacement:=public.create_expense_atomic(expense.tab_id,expense.description,expense.category,change.new_total_centavos,
      COALESCE(payer.user_id,payer.contact_id),shares,expense.due_date,expense.receipt_url);
  END IF;
  INSERT INTO public.expense_change_results(change_id,transaction_id,reversal_id,replacement_id)
    VALUES(change.id,expense.id,first_reversal,replacement);
  INSERT INTO public.expense_change_outputs(transaction_id,change_id,role)
    SELECT value,change.id,'reversal' FROM unnest(reversals) value ON CONFLICT DO NOTHING;
  INSERT INTO public.activity_logs(actor_user_id,tab_id,transaction_id,event_type,metadata)
    VALUES(auth.uid(),expense.tab_id,expense.id,'EXPENSE_CHANGE_APPLIED',jsonb_build_object('change_id',change.id,
      'kind',change.kind,'reason',change.reason,'manual_contact_agreement',change.manual_contact_agreement,
      'reversal_ids',to_jsonb(reversals),'replacement_id',replacement));
  INSERT INTO public.notifications(recipient_user_id,notification_type,related_tab_id,related_transaction_id,title,body)
    SELECT DISTINCT s.user_id,'amount_changed',expense.tab_id,expense.id,'Expense change accepted',
      'Your shared history now includes the agreed revision.' FROM public.transaction_participants s
      WHERE s.transaction_id=expense.id AND s.user_id IS NOT NULL AND s.user_id<>auth.uid();
END $$;
REVOKE ALL ON FUNCTION public.apply_expense_change_internal(uuid) FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.request_expense_change_v2(p_operation_id uuid,p_transaction_id uuid,p_kind text,
  p_new_total bigint,p_reason text,p_expected_actor uuid,p_contact_agreement boolean DEFAULT false)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor uuid:=auth.uid(); expense public.transactions; context jsonb;
  previous public.financial_operations; result uuid; reviewers uuid[]; command jsonb;
BEGIN
  IF actor IS NULL OR actor IS DISTINCT FROM p_expected_actor THEN RAISE EXCEPTION 'Initiating account required' USING ERRCODE='42501'; END IF;
  IF p_operation_id IS NULL OR p_kind IS NULL OR p_kind NOT IN ('correct','cancel') OR p_contact_agreement IS NULL
    OR p_reason IS NULL OR length(trim(p_reason)) NOT BETWEEN 1 AND 500 THEN
    RAISE EXCEPTION 'Valid change identity, kind and reason required' USING ERRCODE='22023'; END IF;
  command:=jsonb_build_object('transaction_id',p_transaction_id,'kind',p_kind,'new_total',p_new_total,'reason',p_reason);
  IF p_contact_agreement THEN command:=command||jsonb_build_object('contact_agreement',true); END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':'||p_operation_id::text,0));
  SELECT * INTO previous FROM public.financial_operations WHERE actor_id=actor AND operation_id=p_operation_id;
  IF FOUND THEN
    IF previous.command_kind<>'expense_change' OR previous.command IS DISTINCT FROM command THEN
      RAISE EXCEPTION 'Operation ID reused with different command' USING ERRCODE='22023'; END IF;
    RETURN previous.result_id;
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(p_transaction_id::text,1));
  SELECT * INTO expense FROM public.transactions WHERE id=p_transaction_id;
  IF expense.id IS NULL OR NOT public.is_tab_member(expense.tab_id,actor) OR NOT EXISTS(
    SELECT 1 FROM public.transaction_participants WHERE transaction_id=expense.id AND user_id=actor) THEN
    RAISE EXCEPTION 'Expense participant required' USING ERRCODE='42501'; END IF;
  context:=public.expense_change_context_internal(expense.id,actor);
  IF context IS NULL OR NOT (context->>'can_request')::boolean THEN RAISE EXCEPTION 'Expense not eligible' USING ERRCODE='22023'; END IF;
  IF (context->>'manual_contact')::boolean IS DISTINCT FROM p_contact_agreement THEN
    RAISE EXCEPTION 'Manual contact changes require explicit outside-app agreement' USING ERRCODE='22023'; END IF;
  IF (p_kind='cancel' AND p_new_total IS NOT NULL) OR (p_kind='correct' AND
    (p_new_total IS NULL OR p_new_total NOT BETWEEN 1 AND 99999999999 OR p_new_total=expense.total_amount_centavos)) THEN
    RAISE EXCEPTION 'Different positive total or cancellation required' USING ERRCODE='22023'; END IF;
  SELECT COALESCE(array_agg(user_id ORDER BY user_id),'{}') INTO reviewers FROM public.transaction_participants
    WHERE transaction_id=expense.id AND user_id IS NOT NULL AND user_id<>actor;
  INSERT INTO public.expense_change_requests(transaction_id,requested_by,reviewer_id,kind,new_total_centavos,reason,original_snapshot,manual_contact_agreement)
    VALUES(expense.id,actor,reviewers[1],p_kind,p_new_total,trim(p_reason),jsonb_build_object('expense',to_jsonb(expense),'shares',
      (SELECT jsonb_agg(to_jsonb(s) ORDER BY s.id) FROM public.transaction_participants s WHERE transaction_id=expense.id)),p_contact_agreement) RETURNING id INTO result;
  INSERT INTO public.expense_change_reviewers SELECT result,value FROM unnest(reviewers) value;
  INSERT INTO public.financial_operations VALUES(actor,p_operation_id,'expense_change',command,result,now());
  IF cardinality(reviewers)=0 THEN
    INSERT INTO public.expense_change_decisions(change_id,actor_id,accepted) VALUES(result,actor,true);
    PERFORM public.apply_expense_change_internal(result);
  ELSE
    INSERT INTO public.notifications(recipient_user_id,notification_type,related_tab_id,related_transaction_id,title,body)
      SELECT value,'amount_proposed',expense.tab_id,expense.id,'Expense change requested','Review a proposed change in your shared tab.' FROM unnest(reviewers) value;
  END IF;
  RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.request_expense_change_v2(uuid,uuid,text,bigint,text,uuid,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.request_expense_change_v2(uuid,uuid,text,bigint,text,uuid,boolean) TO authenticated;
CREATE OR REPLACE FUNCTION public.request_expense_change_v1(p_operation_id uuid,p_transaction_id uuid,p_kind text,p_new_total bigint,p_reason text,p_expected_actor uuid)
RETURNS uuid LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
  SELECT public.request_expense_change_v2(p_operation_id,p_transaction_id,p_kind,p_new_total,p_reason,p_expected_actor,false);
$$;

CREATE OR REPLACE FUNCTION public.decide_expense_change_v1(p_change_id uuid,p_accept boolean,p_expected_actor uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor uuid:=auth.uid(); change public.expense_change_requests; previous public.expense_change_decisions;
BEGIN
  SELECT * INTO change FROM public.expense_change_requests WHERE id=p_change_id;
  IF actor IS NULL OR actor IS DISTINCT FROM p_expected_actor OR change.id IS NULL OR NOT EXISTS(
    SELECT 1 FROM public.expense_change_reviewers WHERE change_id=p_change_id AND reviewer_id=actor)
    OR NOT public.is_tab_member((SELECT tab_id FROM public.transactions WHERE id=change.transaction_id),actor) THEN
    RAISE EXCEPTION 'Registered reviewer required' USING ERRCODE='42501'; END IF;
  IF p_accept IS NULL THEN RAISE EXCEPTION 'Decision required' USING ERRCODE='22023'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(change.transaction_id::text,1));
  SELECT * INTO previous FROM public.expense_change_decisions WHERE change_id=p_change_id AND actor_id=actor;
  IF FOUND THEN
    IF previous.accepted IS DISTINCT FROM p_accept THEN RAISE EXCEPTION 'Decision already recorded' USING ERRCODE='22023'; END IF;
    RETURN change.id;
  END IF;
  IF EXISTS(SELECT 1 FROM public.expense_change_results WHERE transaction_id=change.transaction_id) OR
    EXISTS(SELECT 1 FROM public.expense_change_decisions WHERE change_id=p_change_id AND NOT accepted) THEN
    RAISE EXCEPTION 'Another revision or rejection is final' USING ERRCODE='22023'; END IF;
  INSERT INTO public.expense_change_decisions VALUES(change.id,actor,p_accept,now());
  IF p_accept AND NOT EXISTS(SELECT 1 FROM public.expense_change_reviewers r WHERE r.change_id=p_change_id AND NOT EXISTS(
    SELECT 1 FROM public.expense_change_decisions d WHERE d.change_id=r.change_id AND d.actor_id=r.reviewer_id AND d.accepted)) THEN
    PERFORM public.apply_expense_change_internal(change.id);
  END IF;
  RETURN change.id;
END $$;

CREATE OR REPLACE FUNCTION public.list_expense_changes_v1(p_transaction_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor uuid:=auth.uid(); changes jsonb; context jsonb;
BEGIN
  IF actor IS NULL OR NOT EXISTS(SELECT 1 FROM public.transaction_participants s JOIN public.transactions t ON t.id=s.transaction_id
    WHERE t.id=p_transaction_id AND s.user_id=actor AND public.is_tab_member(t.tab_id,actor)) THEN
    RAISE EXCEPTION 'Expense participant required' USING ERRCODE='42501'; END IF;
  context:=public.expense_change_context_internal(p_transaction_id,actor);
  SELECT COALESCE(jsonb_agg(value ORDER BY created_at,id),'[]') INTO changes FROM (
    SELECT r.created_at,r.id,jsonb_build_object('id',r.id,'transaction_id',r.transaction_id,'requested_by',r.requested_by,
      'reviewer_id',r.reviewer_id,'kind',r.kind,'new_total_centavos',r.new_total_centavos,'reason',r.reason,'created_at',r.created_at,
      'manual_contact_agreement',r.manual_contact_agreement,
      'required_reviewers',(SELECT count(*) FROM public.expense_change_reviewers WHERE change_id=r.id),
      'accepted_reviewers',(SELECT count(*) FROM public.expense_change_reviewers v JOIN public.expense_change_decisions d ON d.change_id=v.change_id AND d.actor_id=v.reviewer_id WHERE v.change_id=r.id AND d.accepted),
      'can_review',o.change_id IS NULL AND NOT EXISTS(SELECT 1 FROM public.expense_change_results WHERE transaction_id=r.transaction_id)
        AND NOT EXISTS(SELECT 1 FROM public.expense_change_decisions WHERE change_id=r.id AND NOT accepted)
        AND EXISTS(SELECT 1 FROM public.expense_change_reviewers WHERE change_id=r.id AND reviewer_id=actor)
        AND NOT EXISTS(SELECT 1 FROM public.expense_change_decisions WHERE change_id=r.id AND actor_id=actor),
      'status',CASE WHEN o.change_id IS NOT NULL THEN 'applied' WHEN EXISTS(SELECT 1 FROM public.expense_change_decisions WHERE change_id=r.id AND NOT accepted) THEN 'rejected'
        WHEN EXISTS(SELECT 1 FROM public.expense_change_results WHERE transaction_id=r.transaction_id) THEN 'superseded' ELSE 'pending' END,
      'reversal_id',o.reversal_id,'replacement_id',o.replacement_id,
      'reversal_ids',(SELECT COALESCE(jsonb_agg(transaction_id ORDER BY transaction_id),'[]') FROM public.expense_change_outputs WHERE change_id=r.id AND role='reversal')) value
    FROM public.expense_change_requests r LEFT JOIN public.expense_change_results o ON o.change_id=r.id WHERE r.transaction_id=p_transaction_id
  ) items;
  RETURN jsonb_build_object('account_id',actor,'transaction_id',p_transaction_id,'changes',changes,
    'can_request',COALESCE((context->>'can_request')::boolean,false),'manual_contact',COALESCE((context->>'manual_contact')::boolean,false));
END $$;
NOTIFY pgrst,'reload schema';
COMMIT;

-- AND-004 bounded ledger reads
BEGIN;
CREATE INDEX IF NOT EXISTS transactions_tab_page ON public.transactions(tab_id,id);
CREATE INDEX IF NOT EXISTS payments_tab_page ON public.payments(tab_id,id);

CREATE FUNCTION public.get_tab_balances_v1(p_tab_ids uuid[]) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor uuid:=auth.uid(); result jsonb;
BEGIN
  IF actor IS NULL OR cardinality(p_tab_ids) IS NULL OR cardinality(p_tab_ids) NOT BETWEEN 1 AND 100
    OR array_position(p_tab_ids,NULL) IS NOT NULL THEN
    RAISE EXCEPTION 'Invalid authenticated tab batch' USING ERRCODE='22023';
  END IF;
  IF EXISTS(SELECT 1 FROM unnest(p_tab_ids) id WHERE NOT public.is_tab_member(id,actor)) THEN
    RAISE EXCEPTION 'Not authorized for every requested tab' USING ERRCODE='42501';
  END IF;
  SELECT jsonb_agg(jsonb_build_object('tab_id',id,'net_balance_centavos',
    public.calculate_user_tab_balance_unchecked(id,actor)) ORDER BY id)
    INTO result FROM (SELECT DISTINCT unnest(p_tab_ids) id) ids;
  RETURN jsonb_build_object('version',1,'account_id',actor,'balances',result);
END $$;

CREATE FUNCTION public.get_tab_ledger_page_v1(p_tab_ids uuid[],p_kind text,
  p_after uuid DEFAULT NULL,p_limit integer DEFAULT 200) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor uuid:=auth.uid(); result jsonb; last_id uuid; more boolean;
BEGIN
  IF actor IS NULL OR cardinality(p_tab_ids) IS NULL OR cardinality(p_tab_ids) NOT BETWEEN 1 AND 100
    OR array_position(p_tab_ids,NULL) IS NOT NULL OR p_kind IS NULL OR p_kind NOT IN ('transactions','payments')
    OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 200 THEN
    RAISE EXCEPTION 'Invalid authenticated history page' USING ERRCODE='22023';
  END IF;
  IF EXISTS(SELECT 1 FROM unnest(p_tab_ids) id WHERE NOT public.is_tab_member(id,actor)) THEN
    RAISE EXCEPTION 'Not authorized for every requested tab' USING ERRCODE='42501';
  END IF;
  IF p_kind='transactions' THEN
    WITH page_window AS (SELECT t.* FROM public.transactions t
      WHERE t.tab_id=ANY(p_tab_ids) AND (p_after IS NULL OR t.id>p_after)
      ORDER BY t.id LIMIT p_limit+1), page AS (SELECT * FROM page_window ORDER BY id LIMIT p_limit)
    SELECT COALESCE(jsonb_agg(jsonb_build_object('id',t.id,'tab_id',t.tab_id,
      'created_by',t.created_by,'transaction_type',t.transaction_type,'category',t.category,
      'description',t.description,'total_amount_centavos',t.total_amount_centavos,
      'currency',t.currency,'due_date',t.due_date,'status',t.status,'created_at',t.created_at,
      'receipt_url',t.receipt_url,'expense_revision',public.expense_revision(ROW(t.*)::public.transactions),
      'transaction_receipt_revisions',COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'storage_path',r.storage_path,'uploaded_at',r.uploaded_at) ORDER BY r.uploaded_at,r.id)
        FROM public.transaction_receipt_revisions r WHERE r.transaction_id=t.id),'[]'::jsonb),
      'transaction_participants',COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'user_id',s.user_id,'contact_id',s.contact_id,'participant_role',s.participant_role,
        'share_amount_centavos',s.share_amount_centavos,'acknowledged',s.acknowledged) ORDER BY s.id)
        FROM public.transaction_participants s WHERE s.transaction_id=t.id),'[]'::jsonb)) ORDER BY t.id),'[]'::jsonb),
      (SELECT id FROM page ORDER BY id DESC LIMIT 1),(SELECT count(*)>p_limit FROM page_window)
      INTO result,last_id,more FROM page t;
  ELSE
    WITH page_window AS (SELECT p.* FROM public.payments p
      WHERE p.tab_id=ANY(p_tab_ids) AND (p_after IS NULL OR p.id>p_after)
      ORDER BY p.id LIMIT p_limit+1), page AS (SELECT * FROM page_window ORDER BY id LIMIT p_limit)
    SELECT COALESCE(jsonb_agg(jsonb_build_object('id',p.id,'tab_id',p.tab_id,
      'submitted_by',p.submitted_by,'payer_user_id',p.payer_user_id,'payer_contact_id',p.payer_contact_id,
      'recipient_user_id',p.recipient_user_id,'recipient_contact_id',p.recipient_contact_id,
      'amount_centavos',p.amount_centavos,'payment_method',p.payment_method,'note',p.note,
      'rejection_reason',p.rejection_reason,'status',p.status,'submitted_at',p.submitted_at,
      'payment_proofs',COALESCE((SELECT jsonb_agg(jsonb_build_object('file_url',f.file_url,
        'reference',f.reference,'uploaded_at',f.uploaded_at) ORDER BY f.uploaded_at,f.id)
        FROM public.payment_proofs f WHERE f.payment_id=p.id),'[]'::jsonb)) ORDER BY p.id),'[]'::jsonb),
      (SELECT id FROM page ORDER BY id DESC LIMIT 1),(SELECT count(*)>p_limit FROM page_window)
      INTO result,last_id,more FROM page p;
  END IF;
  RETURN jsonb_build_object('version',1,'account_id',actor,'kind',p_kind,'records',result,
    'next_cursor',CASE WHEN more THEN last_id ELSE NULL END);
END $$;
REVOKE ALL ON FUNCTION public.get_tab_balances_v1(uuid[]),public.get_tab_ledger_page_v1(uuid[],text,uuid,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_tab_balances_v1(uuid[]),public.get_tab_ledger_page_v1(uuid[],text,uuid,integer) TO authenticated;
COMMIT;

-- SEC-005 reviewed privacy processing
BEGIN;
ALTER TABLE public.users ADD COLUMN anonymized_at timestamptz;
ALTER TABLE public.account_deletion_requests ADD COLUMN reviewed_at timestamptz;
ALTER TABLE public.account_deletion_requests ADD COLUMN completed_at timestamptz;
CREATE TABLE public.account_deletion_objects (
  request_id uuid NOT NULL REFERENCES public.account_deletion_requests(id),
  bucket text NOT NULL CHECK(bucket IN ('profile-avatars','payment-methods')),
  path text NOT NULL, removed_at timestamptz,
  PRIMARY KEY(request_id,bucket,path)
);
ALTER TABLE public.account_deletion_objects ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.account_deletion_objects FROM PUBLIC,anon,authenticated;

-- A soft-deleted Auth identity and immutable financial UUIDs are retained.
-- Already-issued JWTs need a database check; banning/sign-out alone is insufficient.
CREATE FUNCTION public.account_is_active_v1() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
  SELECT NOT EXISTS(SELECT 1 FROM public.users WHERE id=auth.uid() AND anonymized_at IS NOT NULL);
$$;
CREATE FUNCTION public.tabby_pre_request() RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  IF NOT public.account_is_active_v1() THEN
    RAISE EXCEPTION 'Account no longer active' USING ERRCODE='42501';
  END IF;
END $$;
REVOKE ALL ON FUNCTION public.account_is_active_v1(),public.tabby_pre_request() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.account_is_active_v1(),public.tabby_pre_request() TO anon,authenticated,service_role;

CREATE FUNCTION public.block_deleted_actor_v1() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  PERFORM public.tabby_pre_request();
  IF TG_OP='INSERT' AND TG_TABLE_NAME IN ('notifications','reminders') THEN
    IF EXISTS(SELECT 1 FROM public.users WHERE id=NEW.recipient_user_id AND anonymized_at IS NOT NULL) THEN
      RAISE EXCEPTION 'Recipient account no longer active' USING ERRCODE='42501';
    END IF;
  END IF;
  IF TG_OP='INSERT' AND TG_TABLE_NAME='friendships' THEN
    IF EXISTS(SELECT 1 FROM public.users WHERE id IN (NEW.requester_id,NEW.addressee_id) AND anonymized_at IS NOT NULL) THEN
      RAISE EXCEPTION 'Connection account no longer active' USING ERRCODE='42501';
    END IF;
  END IF;
  IF TG_TABLE_NAME='users' AND current_setting('role',true) IN ('anon','authenticated') THEN
    IF (TG_OP='INSERT' AND NEW.anonymized_at IS NOT NULL) OR
       (TG_OP='UPDATE' AND NEW.anonymized_at IS DISTINCT FROM OLD.anonymized_at) THEN
      RAISE EXCEPTION 'Account lifecycle is service managed' USING ERRCODE='42501';
    END IF;
  END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END $$;
REVOKE ALL ON FUNCTION public.block_deleted_actor_v1() FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.protect_profile_identity_v1() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  IF TG_OP='UPDATE' AND OLD.anonymized_at IS NOT NULL THEN NEW.anonymized_at:=OLD.anonymized_at; END IF;
  IF NEW.anonymized_at IS NOT NULL AND current_setting('role',true) NOT IN ('anon','authenticated') THEN
    -- Auth's profile-upsert trigger must not restore PII during soft deletion.
    NEW.display_name:='Former member'; NEW.email:=NULL; NEW.phone:=NULL; NEW.avatar_url:=NULL;
    NEW.gcash_number:=NULL; NEW.maya_number:=NULL; NEW.qr_code_url:=NULL;
    RETURN NEW;
  END IF;
  IF NEW.email IS DISTINCT FROM (CASE WHEN TG_OP='UPDATE' THEN OLD.email ELSE NULL END)
     AND NEW.email IS DISTINCT FROM (SELECT email FROM auth.users WHERE id=NEW.id) THEN
    RAISE EXCEPTION 'Profile email must match Auth' USING ERRCODE='42501';
  END IF;
  IF current_setting('role',true) IN ('anon','authenticated') THEN
    IF TG_OP='INSERT' THEN
      IF coalesce(NEW.gcash_number,'')<>'' OR coalesce(NEW.maya_number,'')<>'' OR coalesce(NEW.qr_code_url,'')<>'' THEN
        RAISE EXCEPTION 'Use saved receiving methods' USING ERRCODE='42501'; END IF;
    ELSIF NEW.gcash_number IS DISTINCT FROM OLD.gcash_number OR NEW.maya_number IS DISTINCT FROM OLD.maya_number
      OR NEW.qr_code_url IS DISTINCT FROM OLD.qr_code_url THEN
      RAISE EXCEPTION 'Use saved receiving methods' USING ERRCODE='42501';
    END IF;
  END IF;
  RETURN NEW;
END $$;

-- Restrictive policies also cover Storage's direct database access, which does
-- not run the PostgREST pre-request hook. Trigger guards cover definer writes.
DO $$ DECLARE t record; existing text;
BEGIN
  FOR t IN SELECT n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE c.relkind IN ('r','p') AND c.relrowsecurity AND n.nspname IN ('public','storage') LOOP
    EXECUTE format('CREATE POLICY tabby_active_actor ON %I.%I AS RESTRICTIVE FOR ALL TO authenticated USING ((SELECT public.account_is_active_v1())) WITH CHECK ((SELECT public.account_is_active_v1()))',t.nspname,t.relname);
    IF t.nspname='public' THEN
      EXECUTE format('CREATE TRIGGER tabby_active_actor BEFORE INSERT OR UPDATE OR DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.block_deleted_actor_v1()',t.relname);
    END IF;
  END LOOP;
  IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticator') THEN
    SELECT value INTO existing FROM pg_db_role_setting s,
      LATERAL unnest(s.setconfig) value WHERE s.setrole=(SELECT oid FROM pg_roles WHERE rolname='authenticator')
      AND s.setdatabase IN (0,(SELECT oid FROM pg_database WHERE datname=current_database()))
      AND value LIKE 'pgrst.db_pre_request=%'
      AND value NOT IN ('pgrst.db_pre_request=','pgrst.db_pre_request=public.tabby_pre_request') LIMIT 1;
    IF existing IS NOT NULL THEN
      RAISE EXCEPTION 'Compose existing pre-request hook before installing privacy lifecycle guard';
    END IF;
    EXECUTE format('ALTER ROLE authenticator IN DATABASE %I SET pgrst.db_pre_request=%L',
      current_database(),'public.tabby_pre_request');
    NOTIFY pgrst,'reload config';
  END IF;
END $$;

CREATE FUNCTION public.review_account_deletion_v1(p_request_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE r public.account_deletion_requests;
BEGIN
  SELECT * INTO STRICT r FROM public.account_deletion_requests WHERE id=p_request_id FOR UPDATE;
  UPDATE public.account_deletion_requests SET reviewed_at=coalesce(reviewed_at,now()) WHERE id=r.id;
  RETURN jsonb_build_object('request_id',r.id,'account_id',r.user_id,'status',r.status,
    'auth_deleted',EXISTS(SELECT 1 FROM auth.users WHERE id=r.user_id AND deleted_at IS NOT NULL));
END $$;

CREATE FUNCTION public.prepare_account_deletion_v1(p_request_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE r public.account_deletion_requests;
BEGIN
  SELECT * INTO STRICT r FROM public.account_deletion_requests WHERE id=p_request_id FOR UPDATE;
  IF r.reviewed_at IS NULL THEN RAISE EXCEPTION 'Review required' USING ERRCODE='42501'; END IF;
  IF r.status='completed' THEN RETURN jsonb_build_object('status',r.status,'account_id',r.user_id); END IF;
  INSERT INTO public.account_deletion_objects(request_id,bucket,path)
    SELECT r.id,o.bucket_id,o.name FROM storage.objects o
    WHERE o.bucket_id IN ('profile-avatars','payment-methods') AND split_part(o.name,'/',1)=r.user_id::text
    ON CONFLICT DO NOTHING;
  UPDATE public.users SET anonymized_at=coalesce(anonymized_at,now()),display_name='Former member',
    email=NULL,phone=NULL,avatar_url=NULL,gcash_number=NULL,maya_number=NULL,qr_code_url=NULL WHERE id=r.user_id;
  UPDATE public.contacts SET display_name='Removed contact',email=NULL,phone=NULL WHERE owner_user_id=r.user_id;
  UPDATE public.payment_methods SET provider='Removed',display_name='Removed',account_label='',qr_storage_path=NULL,
    is_default=false,is_active=false WHERE owner_user_id=r.user_id;
  UPDATE public.payment_method_revisions SET snapshot=jsonb_build_object('id',method_id,'owner_user_id',owner_user_id,
    'revision',revision,'redacted',true) WHERE owner_user_id=r.user_id;
  DELETE FROM public.payment_method_operations WHERE actor_id=r.user_id;
  DELETE FROM public.connection_operations WHERE owner_id=r.user_id;
  DELETE FROM public.connection_preferences WHERE owner_id=r.user_id;
  DELETE FROM public.push_device_bindings WHERE user_id=r.user_id;
  UPDATE public.push_delivery_jobs SET status='cancelled',lease_id=NULL,lease_until=NULL
    WHERE user_id=r.user_id AND status IN ('pending','sending');
  UPDATE public.notifications SET title='Removed account notice',body='' WHERE recipient_user_id=r.user_id;
  UPDATE public.reminders SET status='cancelled' WHERE (created_by=r.user_id OR recipient_user_id=r.user_id) AND status='scheduled';
  DELETE FROM public.friendships WHERE requester_id=r.user_id OR addressee_id=r.user_id;
  UPDATE public.account_deletion_requests SET status='processing' WHERE id=r.id;
  RETURN jsonb_build_object('status','processing','account_id',r.user_id);
END $$;

CREATE FUNCTION public.pending_deletion_objects_v1(p_request_id uuid) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
  SELECT coalesce(jsonb_agg(jsonb_build_object('bucket',bucket,'path',path) ORDER BY bucket,path),'[]'::jsonb)
    FROM (SELECT bucket,path FROM public.account_deletion_objects
      WHERE request_id=p_request_id AND removed_at IS NULL ORDER BY bucket,path LIMIT 100) page;
$$;
CREATE FUNCTION public.acknowledge_deletion_object_v1(p_request_id uuid,p_bucket text,p_path text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  IF EXISTS(SELECT 1 FROM storage.objects WHERE bucket_id=p_bucket AND name=p_path) THEN
    RAISE EXCEPTION 'Object removal not confirmed' USING ERRCODE='55000'; END IF;
  UPDATE public.account_deletion_objects SET removed_at=coalesce(removed_at,now())
    WHERE request_id=p_request_id AND bucket=p_bucket AND path=p_path;
  RETURN FOUND;
END $$;

CREATE FUNCTION public.finish_account_deletion_v1(p_request_id uuid) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE r public.account_deletion_requests;
BEGIN
  SELECT * INTO STRICT r FROM public.account_deletion_requests WHERE id=p_request_id FOR UPDATE;
  IF r.status='completed' THEN RETURN true; END IF;
  IF r.status<>'processing' OR r.reviewed_at IS NULL OR
    NOT EXISTS(SELECT 1 FROM public.users WHERE id=r.user_id AND anonymized_at IS NOT NULL) OR
    NOT EXISTS(SELECT 1 FROM auth.users WHERE id=r.user_id AND deleted_at IS NOT NULL) OR
    EXISTS(SELECT 1 FROM auth.sessions WHERE user_id=r.user_id) OR
    EXISTS(SELECT 1 FROM public.account_deletion_objects WHERE request_id=r.id AND removed_at IS NULL) OR
    EXISTS(SELECT 1 FROM storage.objects WHERE bucket_id IN ('profile-avatars','payment-methods')
      AND split_part(name,'/',1)=r.user_id::text) THEN
    RAISE EXCEPTION 'Deletion processing incomplete' USING ERRCODE='55000';
  END IF;
  UPDATE public.account_deletion_requests SET status='completed',completed_at=now() WHERE id=r.id;
  RETURN true;
END $$;
REVOKE ALL ON FUNCTION public.review_account_deletion_v1(uuid),public.prepare_account_deletion_v1(uuid),
 public.pending_deletion_objects_v1(uuid),public.acknowledge_deletion_object_v1(uuid,text,text),
 public.finish_account_deletion_v1(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.review_account_deletion_v1(uuid),public.prepare_account_deletion_v1(uuid),
 public.pending_deletion_objects_v1(uuid),public.acknowledge_deletion_object_v1(uuid,text,text),
 public.finish_account_deletion_v1(uuid) TO service_role;

CREATE FUNCTION public.reject_anonymized_participant_v1() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND EXISTS(SELECT 1 FROM public.users WHERE id=NEW.user_id AND anonymized_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Cannot add a new share for an inactive account' USING ERRCODE='42501'; END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.reject_anonymized_participant_v1() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER reject_anonymized_participant BEFORE INSERT ON public.transaction_participants
  FOR EACH ROW EXECUTE FUNCTION public.reject_anonymized_participant_v1();

CREATE FUNCTION public.export_private_page_v1(p_section text,p_after uuid DEFAULT NULL,p_limit integer DEFAULT 50)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor uuid:=auth.uid(); records jsonb; last_id uuid; more boolean;
BEGIN
  PERFORM public.tabby_pre_request();
  IF actor IS NULL THEN RAISE EXCEPTION 'Sign in required' USING ERRCODE='42501'; END IF;
  IF p_section IS NULL OR p_section NOT IN ('receiving_methods','connections','contacts','notifications','reminders') OR
    p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN
    RAISE EXCEPTION 'Invalid private export page' USING ERRCODE='22023'; END IF;
  WITH scoped AS (
    SELECT p.id,jsonb_build_object('id',p.id,'provider',p.provider,'display_name',p.display_name,
      'account_label',p.account_label,'is_active',p.is_active,'is_default',p.is_default) record
      FROM public.payment_methods p WHERE p.owner_user_id=actor AND p_section='receiving_methods'
    UNION ALL SELECT c.id,jsonb_build_object('id',c.id,'display_name',c.display_name,'phone',c.phone,'email',c.email)
      FROM public.contacts c WHERE c.owner_user_id=actor AND p_section='contacts'
    UNION ALL SELECT c.owner_id,jsonb_build_object('id',c.owner_id,'nicknames',c.nicknames,'archived_tab_ids',c.archived_tab_ids)
      FROM public.connection_preferences c WHERE c.owner_id=actor AND p_section='connections'
    UNION ALL SELECT n.id,jsonb_build_object('id',n.id,'type',n.notification_type,'title',n.title,'body',n.body,
      'created_at',n.created_at,'is_read',n.is_read) FROM public.notifications n
      WHERE n.recipient_user_id=actor AND p_section='notifications'
    UNION ALL SELECT r.id,jsonb_build_object('id',r.id,'transaction_id',r.transaction_id,'type',r.reminder_type,
      'scheduled_for',r.scheduled_for,'status',r.status) FROM public.reminders r
      WHERE r.recipient_user_id=actor AND p_section='reminders'
  ), page_window AS (SELECT * FROM scoped WHERE p_after IS NULL OR id>p_after ORDER BY id LIMIT p_limit+1),
  page AS (SELECT * FROM page_window ORDER BY id LIMIT p_limit)
  SELECT coalesce(jsonb_agg(record ORDER BY id),'[]'::jsonb),
    (SELECT id FROM page ORDER BY id DESC LIMIT 1),(SELECT count(*)>p_limit FROM page_window)
    INTO records,last_id,more FROM page;
  RETURN jsonb_build_object('version',1,'account_id',actor,'section',p_section,'records',records,
    'next_cursor',CASE WHEN more THEN last_id ELSE NULL END);
END $$;
REVOKE ALL ON FUNCTION public.export_private_page_v1(text,uuid,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.export_private_page_v1(text,uuid,integer) TO authenticated;
CREATE OR REPLACE FUNCTION public.is_tab_member(p_tab_id UUID, p_user_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    IF NOT public.account_is_active_v1() THEN RETURN FALSE; END IF;
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
ALTER FUNCTION public.is_tab_member(uuid,uuid) SET search_path=pg_catalog,public;
CREATE OR REPLACE FUNCTION public.is_group_member(p_group_id UUID, p_user_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    IF NOT public.account_is_active_v1() THEN RETURN FALSE; END IF;
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
ALTER FUNCTION public.is_group_member(uuid,uuid) SET search_path=pg_catalog,public;
CREATE OR REPLACE FUNCTION public.is_group_admin(p_group_id UUID, p_user_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    IF NOT public.account_is_active_v1() THEN RETURN FALSE; END IF;
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
ALTER FUNCTION public.is_group_admin(uuid,uuid) SET search_path=pg_catalog,public;

-- Guarded replacements for pre-existing privacy RPCs follow below.

-- Intentionally limited personal-data export. Shared ledger/media need a
-- separate paginated export contract; do not expose arbitrary row JSON.
CREATE OR REPLACE FUNCTION public.export_account_data_v1()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public AS $$
DECLARE actor uuid := auth.uid(); result jsonb;
BEGIN
  PERFORM public.tabby_pre_request();
  IF actor IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;
  SELECT jsonb_build_object(
    'version', 1, 'account_id', actor, 'generated_at', statement_timestamp(),
    'scope', 'profile_and_owned_contacts',
    'excluded', jsonb_build_array('shared_ledger', 'payment_methods',
      'media', 'notifications', 'authentication_records', 'local_drafts'),
    'profile', (SELECT jsonb_build_object(
      'id', u.id, 'display_name', u.display_name, 'email', u.email,
      'phone', u.phone, 'created_at', u.created_at)
      FROM public.users u WHERE u.id = actor),
    'contacts', COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id', c.id, 'display_name', c.display_name, 'email', c.email,
      'phone', c.phone, 'created_at', c.created_at) ORDER BY c.id)
      FROM public.contacts c WHERE c.owner_user_id = actor), '[]'::jsonb)
  ) INTO result;
  RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.export_account_data_v1() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.export_account_data_v1() TO authenticated;

-- No target-account argument: the server chooses scope from the JWT subject.
-- Explicit projections avoid exporting storage URLs or newly added columns.
CREATE OR REPLACE FUNCTION public.export_ledger_page_v1(
  p_section text, p_after uuid DEFAULT NULL, p_limit integer DEFAULT 50
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public AS $$
DECLARE actor uuid := auth.uid(); rows jsonb; last_id uuid; has_more boolean;
BEGIN
  PERFORM public.tabby_pre_request();
  IF actor IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;
  IF p_section IS NULL OR p_section NOT IN ('tabs', 'expenses', 'shares', 'payments')
    OR p_limit IS NULL OR p_limit < 1 OR p_limit > 100 THEN
    RAISE EXCEPTION 'Invalid export section or page size' USING ERRCODE = '22023';
  END IF;
  WITH authorized_tabs AS (
    SELECT t.id FROM public.tabs t
    WHERE t.user_a = actor OR t.user_b = actor OR EXISTS (
      SELECT 1 FROM public.tab_members m WHERE m.tab_id = t.id AND m.user_id = actor)
  ), scoped AS (
    SELECT t.id, jsonb_build_object('id',t.id, 'type',t.tab_type,
      'status',t.status, 'group_id',t.group_id, 'user_a',t.user_a,
      'user_b',t.user_b, 'created_at',t.created_at) AS record
    FROM public.tabs t JOIN authorized_tabs a ON a.id = t.id
    WHERE p_section = 'tabs'
    UNION ALL
    SELECT t.id, jsonb_build_object('id',t.id, 'tab_id',t.tab_id,
      'created_by',t.created_by, 'description',t.description,
      'category',t.category, 'status',t.status, 'total_amount_centavos',t.total_amount_centavos,
      'currency',t.currency, 'transaction_date',t.transaction_date,
      'due_date',t.due_date, 'created_at',t.created_at)
    FROM public.transactions t JOIN authorized_tabs a ON a.id = t.tab_id
    WHERE p_section = 'expenses'
    UNION ALL
    SELECT s.id, jsonb_build_object('id',s.id, 'transaction_id',s.transaction_id,
      'user_id',s.user_id, 'contact_id',s.contact_id,
      'role',s.participant_role, 'share_amount_centavos',s.share_amount_centavos,
      'acknowledged',s.acknowledged, 'acknowledged_at',s.acknowledged_at)
    FROM public.transaction_participants s
    JOIN public.transactions t ON t.id = s.transaction_id
    JOIN authorized_tabs a ON a.id = t.tab_id
    WHERE p_section = 'shares'
    UNION ALL
    SELECT p.id, jsonb_build_object('id',p.id, 'tab_id',p.tab_id,
      'submitted_by',p.submitted_by, 'recipient_user_id',p.recipient_user_id,
      'amount_centavos',p.amount_centavos, 'payment_method',p.payment_method,
      'note',p.note, 'status',p.status, 'submitted_at',p.submitted_at,
      'confirmed_by',p.confirmed_by, 'confirmed_at',p.confirmed_at)
    FROM public.payments p JOIN authorized_tabs a ON a.id = p.tab_id
    WHERE p_section = 'payments'
  ), page_window AS (
    SELECT * FROM scoped WHERE p_after IS NULL OR id > p_after
    ORDER BY id LIMIT p_limit + 1
  ), page AS (
    SELECT * FROM page_window ORDER BY id LIMIT p_limit
  )
  SELECT COALESCE((SELECT jsonb_agg(record ORDER BY id) FROM page),'[]'::jsonb),
    (SELECT id FROM page ORDER BY id DESC LIMIT 1),
    (SELECT count(*) > p_limit FROM page_window)
  INTO rows, last_id, has_more;
  RETURN jsonb_build_object('version',1, 'account_id',actor,
    'section',p_section, 'records',rows,
    'next_cursor',CASE WHEN has_more THEN last_id ELSE NULL END,
    'generated_at',statement_timestamp(),
    'consistency','Each page is a current read, not a whole-export snapshot.');
END $$;
REVOKE ALL ON FUNCTION public.export_ledger_page_v1(text,uuid,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.export_ledger_page_v1(text,uuid,integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_account_deletion_request_v1()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public AS $$
DECLARE actor uuid := auth.uid(); result jsonb;
BEGIN
  PERFORM public.tabby_pre_request();
  IF actor IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;
  SELECT jsonb_build_object('id',r.id,'account_id',actor,
    'requested_at',r.requested_at,'status',r.status)
  INTO result FROM public.account_deletion_requests r WHERE r.user_id = actor;
  RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_account_deletion_request_v1() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_account_deletion_request_v1() TO authenticated;

CREATE OR REPLACE FUNCTION public.request_account_deletion_v1()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public AS $$
DECLARE actor uuid := auth.uid(); request public.account_deletion_requests;
BEGIN
  PERFORM public.tabby_pre_request();
  IF actor IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;
  -- AMR timestamps describe actual authentication, unlike refreshed-token iat.
  -- Claims come from the verified JWT at the PostgREST boundary.
  IF NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(COALESCE(auth.jwt()->'amr', '[]'::jsonb)) m
    WHERE m->>'method' IN ('password', 'otp', 'oauth', 'totp', 'sso/saml')
      AND CASE WHEN m->>'timestamp' ~ '^[0-9]{1,12}$'
        THEN (m->>'timestamp')::bigint
          BETWEEN extract(epoch FROM statement_timestamp())::bigint - 300
          AND extract(epoch FROM statement_timestamp())::bigint + 30
        ELSE false END
  ) THEN
    RAISE EXCEPTION 'Sign in again before requesting account deletion' USING ERRCODE = '42501';
  END IF;
  INSERT INTO public.account_deletion_requests(user_id) VALUES (actor)
    ON CONFLICT (user_id) DO NOTHING;
  SELECT * INTO STRICT request FROM public.account_deletion_requests WHERE user_id = actor;
  RETURN jsonb_build_object('id', request.id, 'account_id', actor,
    'requested_at', request.requested_at, 'status', request.status);
END $$;
REVOKE ALL ON FUNCTION public.request_account_deletion_v1() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_account_deletion_v1() TO authenticated;

COMMIT;

-- M2 custom splits (rollout disabled)
BEGIN;
CREATE TABLE public.m2_feature_flags(feature text PRIMARY KEY, enabled boolean NOT NULL DEFAULT false);
INSERT INTO public.m2_feature_flags(feature) VALUES('custom_splits'),('recurring'),('contact_claiming'),('expense_review');
ALTER TABLE public.m2_feature_flags ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.m2_feature_flags FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.require_m2_v1(p_feature text,p_operation uuid,p_command jsonb,p_kind text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor uuid:=auth.uid(); prior public.financial_operations;
BEGIN
  PERFORM public.tabby_pre_request();
  IF actor IS NULL OR actor IS DISTINCT FROM (p_command->>'p_expected_actor')::uuid THEN
    RAISE EXCEPTION 'Account changed' USING ERRCODE='42501'; END IF;
  IF NOT coalesce((SELECT enabled FROM public.m2_feature_flags WHERE feature=p_feature),false) THEN
    RAISE EXCEPTION 'Feature awaiting acceptance' USING ERRCODE='42501'; END IF;
  IF p_operation IS NULL OR p_command IS NULL OR jsonb_typeof(p_command)<>'object' THEN
    RAISE EXCEPTION 'Operation and command required' USING ERRCODE='22023'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':'||p_operation::text,0));
  SELECT * INTO prior FROM public.financial_operations WHERE actor_id=actor AND operation_id=p_operation;
  IF FOUND THEN
    IF prior.command_kind<>p_kind OR prior.command IS DISTINCT FROM p_command THEN
      RAISE EXCEPTION 'Operation payload conflict' USING ERRCODE='22023'; END IF;
    RETURN prior.result_id;
  END IF;
  RETURN NULL;
END $$;
CREATE FUNCTION public.record_m2_v1(p_operation uuid,p_kind text,p_command jsonb,p_result uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  INSERT INTO public.financial_operations(actor_id,operation_id,command_kind,command,result_id)
    VALUES(auth.uid(),p_operation,p_kind,p_command,p_result);
  RETURN p_result;
END $$;
REVOKE ALL ON FUNCTION public.require_m2_v1(text,uuid,jsonb,text),public.record_m2_v1(uuid,text,jsonb,uuid) FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.allocate_custom_split_v1(p_split jsonb,p_payer uuid) RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog,public AS $$
DECLARE base bigint; tax_rate integer; fee_rate integer; tax bigint; fee bigint; n integer; parts jsonb;
BEGIN
  IF p_split IS NULL OR jsonb_typeof(p_split)<>'object' OR
    p_split-ARRAY['base_centavos','tax_basis_points','service_basis_points','base_shares']<>'{}'::jsonb OR
    coalesce(p_split->>'base_centavos','')!~'^[0-9]{1,11}$' OR
    coalesce(p_split->>'tax_basis_points','')!~'^[0-9]{1,5}$' OR
    coalesce(p_split->>'service_basis_points','')!~'^[0-9]{1,5}$' OR
    jsonb_typeof(p_split->'base_shares') IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'Invalid split' USING ERRCODE='22023'; END IF;
  base:=(p_split->>'base_centavos')::bigint; tax_rate:=(p_split->>'tax_basis_points')::integer;
  fee_rate:=(p_split->>'service_basis_points')::integer; n:=jsonb_array_length(p_split->'base_shares');
  IF base NOT BETWEEN 1 AND 99999999999 OR tax_rate NOT BETWEEN 0 AND 10000 OR fee_rate NOT BETWEEN 0 AND 10000 OR n NOT BETWEEN 1 AND 100 THEN
    RAISE EXCEPTION 'Split outside supported limits' USING ERRCODE='22023'; END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_split->'base_shares') b WHERE
    jsonb_typeof(b)<>'object' OR b-ARRAY['party','amount']<>'{}'::jsonb OR
    coalesce(b->>'amount','')!~'^[0-9]{1,11}$' OR
    coalesce(b->'party'->>'kind','') NOT IN ('user','contact') OR
    coalesce(b->'party'->>'id','')!~'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') OR
    (SELECT count(DISTINCT b->'party'->>'id') FROM jsonb_array_elements(p_split->'base_shares') b)<>n OR
    (SELECT sum((b->>'amount')::bigint) FROM jsonb_array_elements(p_split->'base_shares') b)<>base OR
    NOT EXISTS(SELECT 1 FROM jsonb_array_elements(p_split->'base_shares') b WHERE b->'party'->>'id'=p_payer::text) THEN
    RAISE EXCEPTION 'Invalid or duplicate parties/base shares' USING ERRCODE='22023'; END IF;
  tax:=round(base::numeric*tax_rate/10000)::bigint; fee:=round(base::numeric*fee_rate/10000)::bigint;
  IF base+tax+fee>99999999999 THEN RAISE EXCEPTION 'Total outside supported limit' USING ERRCODE='22023'; END IF;
  WITH weights AS (SELECT b->'party' party,(b->>'amount')::bigint amount,
    b->'party'->>'kind'||':'||(b->'party'->>'id') identity FROM jsonb_array_elements(p_split->'base_shares') b),
  floors AS (SELECT *,floor(tax::numeric*amount/base)::bigint t,floor(fee::numeric*amount/base)::bigint f,
    mod(tax::numeric*amount,base) tr,mod(fee::numeric*amount,base) fr FROM weights),
  ranked AS (SELECT *,row_number() OVER(ORDER BY tr DESC,identity) tn,row_number() OVER(ORDER BY fr DESC,identity) fn,
    tax-sum(t) OVER() tl,fee-sum(f) OVER() fl FROM floors)
  SELECT jsonb_agg(jsonb_build_object(CASE WHEN party->>'kind'='user' THEN 'user_id' ELSE 'contact_id' END,
    party->>'id','participant_role',CASE WHEN party->>'id'=p_payer::text THEN 'payer' ELSE 'debtor' END,
    'share_amount_centavos',amount+t+f+CASE WHEN tn<=tl THEN 1 ELSE 0 END+CASE WHEN fn<=fl THEN 1 ELSE 0 END,
    'acknowledged',false) ORDER BY identity) INTO parts FROM ranked;
  RETURN jsonb_build_object('base_centavos',base,'tax_centavos',tax,'service_centavos',fee,
    'total_centavos',base+tax+fee,'participants',parts);
END $$;
REVOKE ALL ON FUNCTION public.allocate_custom_split_v1(jsonb,uuid) FROM PUBLIC,anon,authenticated;

CREATE TABLE public.expense_split_details(transaction_id uuid PRIMARY KEY REFERENCES public.transactions(id) ON DELETE RESTRICT,
  breakdown jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now());
ALTER TABLE public.expense_split_details ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.expense_split_details FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.expense_split_details TO authenticated;
CREATE FUNCTION public.can_read_expense_split_v1(p_transaction uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
  SELECT auth.uid() IS NOT NULL AND EXISTS(SELECT 1 FROM public.transactions t
    WHERE t.id=p_transaction AND public.is_tab_member(t.tab_id,auth.uid()));
$$;
REVOKE ALL ON FUNCTION public.can_read_expense_split_v1(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_read_expense_split_v1(uuid) TO authenticated;
CREATE POLICY split_participant_read ON public.expense_split_details FOR SELECT TO authenticated USING(
  public.can_read_expense_split_v1(transaction_id));
CREATE POLICY tabby_active_actor ON public.expense_split_details AS RESTRICTIVE FOR ALL TO authenticated
  USING((SELECT public.account_is_active_v1())) WITH CHECK((SELECT public.account_is_active_v1()));

CREATE FUNCTION public.validate_expense_roster_v2(p_tab uuid,p_parts jsonb,p_actor uuid) RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE tab public.tabs; part jsonb; u uuid; c uuid;
BEGIN
  SELECT * INTO tab FROM public.tabs WHERE id=p_tab;
  IF tab.id IS NULL OR tab.status<>'active' OR NOT public.is_tab_member(p_tab,p_actor) OR
    NOT EXISTS(SELECT 1 FROM public.users WHERE id=p_actor AND anonymized_at IS NULL) OR
    (tab.group_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.group_members
      WHERE group_id=tab.group_id AND user_id=p_actor AND status='active')) THEN
    RAISE EXCEPTION 'Active tab membership required' USING ERRCODE='42501'; END IF;
  IF jsonb_typeof(p_parts) IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Explicit shares required' USING ERRCODE='22023'; END IF;
  FOR part IN SELECT value FROM jsonb_array_elements(p_parts) LOOP
    u:=nullif(part->>'user_id','')::uuid;c:=nullif(part->>'contact_id','')::uuid;
    IF (u IS NULL)=(c IS NULL) THEN RAISE EXCEPTION 'One party identity required' USING ERRCODE='22023'; END IF;
    IF u IS NOT NULL AND (NOT public.is_tab_member(p_tab,u) OR
      NOT EXISTS(SELECT 1 FROM public.users WHERE id=u AND anonymized_at IS NULL) OR
      (tab.group_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.group_members WHERE group_id=tab.group_id AND user_id=u AND status='active'))) THEN
      RAISE EXCEPTION 'Participant no longer active in this group' USING ERRCODE='42501'; END IF;
    IF c IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.contacts contact JOIN public.tab_members m ON m.contact_id=contact.id
      WHERE contact.id=c AND contact.owner_user_id=p_actor AND contact.claim_status='unclaimed'
        AND m.tab_id=p_tab AND tab.tab_type='individual' AND tab.group_id IS NULL) THEN
      RAISE EXCEPTION 'Owned unclaimed contact required' USING ERRCODE='42501'; END IF;
  END LOOP;
END $$;
REVOKE ALL ON FUNCTION public.validate_expense_roster_v2(uuid,jsonb,uuid) FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.create_expense_v3(p_operation_id uuid,p_command jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE result uuid; split jsonb;
BEGIN
  result:=public.require_m2_v1('custom_splits',p_operation_id,p_command,'m2_custom_split');
  IF result IS NOT NULL THEN RETURN result; END IF;
  IF NOT public.is_tab_member((p_command->>'p_tab_id')::uuid,auth.uid()) THEN
    RAISE EXCEPTION 'Tab membership required' USING ERRCODE='42501'; END IF;
  IF p_command-ARRAY['p_expected_actor','p_tab_id','p_description','p_category','p_total_amount_centavos',
    'p_paid_by_user_id','p_participants','p_due_date','p_receipt_url','split']<>'{}'::jsonb THEN
    RAISE EXCEPTION 'Unsupported split fields' USING ERRCODE='22023'; END IF;
  split:=public.allocate_custom_split_v1(p_command->'split',(p_command->>'p_paid_by_user_id')::uuid);
  PERFORM public.validate_expense_roster_v2((p_command->>'p_tab_id')::uuid,split->'participants',auth.uid());
  IF coalesce(p_command->>'p_total_amount_centavos','')!~'^[0-9]{1,11}$' OR
    (p_command->>'p_total_amount_centavos')::bigint<>(split->>'total_centavos')::bigint OR
    jsonb_typeof(p_command->'p_participants') IS DISTINCT FROM 'array' OR
    jsonb_array_length(p_command->'p_participants')<>jsonb_array_length(split->'participants') OR
    EXISTS(SELECT 1 FROM jsonb_array_elements(split->'participants') expected WHERE
      (SELECT count(*) FROM jsonb_array_elements(p_command->'p_participants') actual WHERE actual=expected)<>1) THEN
    RAISE EXCEPTION 'Submitted allocation differs from calculated total' USING ERRCODE='22023'; END IF;
  result:=public.create_expense_atomic((p_command->>'p_tab_id')::uuid,p_command->>'p_description',
    p_command->>'p_category',(split->>'total_centavos')::bigint,(p_command->>'p_paid_by_user_id')::uuid,
    split->'participants',(p_command->>'p_due_date')::date,p_command->>'p_receipt_url');
  INSERT INTO public.expense_split_details VALUES(result,(p_command->'split')||split,now());
  RETURN public.record_m2_v1(p_operation_id,'m2_custom_split',p_command,result);
END $$;
REVOKE ALL ON FUNCTION public.create_expense_v3(uuid,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_expense_v3(uuid,jsonb) TO authenticated;

-- Fresh M1 writes also require current roster; historical rows stay intact.
CREATE OR REPLACE FUNCTION public.execute_money_command_v1(
    p_operation_id UUID, p_kind TEXT, p_command JSONB
) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
    v_actor UUID := auth.uid();
    v_original public.financial_operations%ROWTYPE;
    v_result UUID;
BEGIN
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;
    IF p_operation_id IS NULL OR p_command IS NULL
       OR jsonb_typeof(p_command) <> 'object' THEN
        RAISE EXCEPTION 'Operation ID and command object required' USING ERRCODE = '22023';
    END IF;
    IF NOT public.is_tab_member((p_command->>'p_tab_id')::UUID, v_actor) THEN
        RAISE EXCEPTION 'Tab membership required' USING ERRCODE = '42501';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtextextended(v_actor::TEXT || ':' || p_operation_id::TEXT, 0));
    SELECT * INTO v_original FROM public.financial_operations
        WHERE actor_id = v_actor AND operation_id = p_operation_id;
    IF FOUND THEN
        IF v_original.command_kind IS DISTINCT FROM p_kind
           OR v_original.command IS DISTINCT FROM p_command THEN
            RAISE EXCEPTION 'Operation ID reused with a different command' USING ERRCODE = '22023';
        END IF;
        RETURN v_original.result_id;
    END IF;
    IF p_kind = 'expense' THEN
        PERFORM public.validate_expense_roster_v2((p_command->>'p_tab_id')::uuid,p_command->'p_participants',v_actor);
        v_result := public.create_expense_atomic(
            (p_command->>'p_tab_id')::UUID, p_command->>'p_description',
            p_command->>'p_category', (p_command->>'p_total_amount_centavos')::BIGINT,
            (p_command->>'p_paid_by_user_id')::UUID, p_command->'p_participants',
            (p_command->>'p_due_date')::DATE, p_command->>'p_receipt_url');
    ELSIF p_kind = 'payment' THEN
        v_result := public.submit_payment(
            (p_command->>'p_tab_id')::UUID, (p_command->>'p_submitted_by_user_id')::UUID,
            (p_command->>'p_recipient_user_id')::UUID, (p_command->>'p_amount_centavos')::BIGINT,
            p_command->>'p_payment_method', p_command->>'p_note');
    ELSE
        RAISE EXCEPTION 'Unsupported money command' USING ERRCODE = '22023';
    END IF;
    INSERT INTO public.financial_operations(actor_id, operation_id, command_kind, command, result_id)
        VALUES (v_actor, p_operation_id, p_kind, p_command, v_result);
    RETURN v_result;
END;
$$;
COMMIT;

-- M2 recurring obligations (rollout disabled)
BEGIN;
CREATE OR REPLACE FUNCTION public.require_m2_v1(p_feature text,p_operation uuid,p_command jsonb,p_kind text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor uuid:=auth.uid(); prior public.financial_operations;
BEGIN
  IF actor IS NOT NULL THEN PERFORM pg_advisory_xact_lock(hashtextextended('account-lifecycle:'||actor::text,0)); END IF;
  PERFORM public.tabby_pre_request();
  IF actor IS NULL OR actor IS DISTINCT FROM (p_command->>'p_expected_actor')::uuid THEN
    RAISE EXCEPTION 'Account changed' USING ERRCODE='42501'; END IF;
  IF NOT coalesce((SELECT enabled FROM public.m2_feature_flags WHERE feature=p_feature),false) THEN
    RAISE EXCEPTION 'Feature awaiting acceptance' USING ERRCODE='42501'; END IF;
  IF p_operation IS NULL OR p_command IS NULL OR jsonb_typeof(p_command)<>'object' THEN
    RAISE EXCEPTION 'Operation and command required' USING ERRCODE='22023'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':'||p_operation::text,0));
  SELECT * INTO prior FROM public.financial_operations WHERE actor_id=actor AND operation_id=p_operation;
  IF FOUND THEN
    IF prior.command_kind<>p_kind OR prior.command IS DISTINCT FROM p_command THEN
      RAISE EXCEPTION 'Operation payload conflict' USING ERRCODE='22023'; END IF;
    RETURN prior.result_id;
  END IF;
  RETURN NULL;
END $$;

CREATE TABLE public.recurrence_rules(
  id uuid PRIMARY KEY,owner_id uuid NOT NULL REFERENCES public.users(id),tab_id uuid NOT NULL REFERENCES public.tabs(id),
  anchor date NOT NULL,timezone text NOT NULL,unit text NOT NULL CHECK(unit IN ('daily','weekly','monthly')),
  step integer NOT NULL CHECK(step BETWEEN 1 AND 120),end_date date,template jsonb NOT NULL,
  status text NOT NULL DEFAULT 'active' CHECK(status IN ('active','paused','ended','needs_attention')),
  revision integer NOT NULL DEFAULT 1,effective_from date NOT NULL,next_index integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.recurrence_events(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),rule_id uuid NOT NULL REFERENCES public.recurrence_rules(id),
  revision integer NOT NULL,action text NOT NULL,snapshot jsonb NOT NULL,created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.recurrence_occurrences(rule_id uuid NOT NULL REFERENCES public.recurrence_rules(id),occurrence_date date NOT NULL,
  transaction_id uuid NOT NULL UNIQUE REFERENCES public.transactions(id),rule_revision integer NOT NULL,
  source text NOT NULL CHECK(source IN ('owner','scheduler')),created_at timestamptz NOT NULL DEFAULT now(),PRIMARY KEY(rule_id,occurrence_date));
ALTER TABLE public.recurrence_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recurrence_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recurrence_occurrences ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.recurrence_rules,public.recurrence_events,public.recurrence_occurrences FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.recurrence_date_v1(p_anchor date,p_unit text,p_step integer,p_index integer) RETURNS date
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog,public AS $$
BEGIN
  IF p_step IS NULL OR p_step NOT BETWEEN 1 AND 120 OR p_index IS NULL OR p_index NOT BETWEEN 0 AND 120000 OR p_anchor IS NULL THEN
    RAISE EXCEPTION 'Invalid recurrence calendar' USING ERRCODE='22023'; END IF;
  IF p_unit='monthly' THEN RETURN (p_anchor+make_interval(months=>p_step*p_index))::date;
  ELSIF p_unit='weekly' THEN RETURN p_anchor+(7*p_step*p_index);
  ELSIF p_unit='daily' THEN RETURN p_anchor+(p_step*p_index);
  ELSE RAISE EXCEPTION 'Invalid recurrence unit' USING ERRCODE='22023'; END IF;
END $$;
CREATE FUNCTION public.recurrence_index_v1(p_anchor date,p_unit text,p_step integer,p_day date) RETURNS integer
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog,public AS $$
DECLARE n integer;
BEGIN
  IF p_unit='monthly' THEN
    n:=greatest(0,((extract(year FROM p_day)::int-extract(year FROM p_anchor)::int)*12+
      extract(month FROM p_day)::int-extract(month FROM p_anchor)::int)/p_step);
  ELSE n:=greatest(0,(p_day-p_anchor)/(p_step*CASE WHEN p_unit='weekly' THEN 7 ELSE 1 END)); END IF;
  IF public.recurrence_date_v1(p_anchor,p_unit,p_step,n)<p_day THEN n:=n+1; END IF;
  RETURN n;
END $$;
REVOKE ALL ON FUNCTION public.recurrence_date_v1(date,text,integer,integer),public.recurrence_index_v1(date,text,integer,date) FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.change_recurrence_v1(p_operation_id uuid,p_command jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE result uuid; r public.recurrence_rules; action text:=p_command->>'action'; anchor date; zone text; unit text;
  step integer; ending date; template jsonb; allocated jsonb; today date;
BEGIN
  result:=public.require_m2_v1('recurring',p_operation_id,p_command,'m2_recurrence');IF result IS NOT NULL THEN RETURN result; END IF;
  IF p_command-ARRAY['p_expected_actor','action','rule_id','expected_revision','p_tab_id','anchor','timezone','unit','step','end_date','template']<>'{}'::jsonb THEN
    RAISE EXCEPTION 'Unsupported rule fields' USING ERRCODE='22023'; END IF;
  IF action IS NULL OR action NOT IN ('create','edit','pause','resume','end') THEN RAISE EXCEPTION 'Invalid rule action' USING ERRCODE='22023'; END IF;
  SELECT * INTO r FROM public.recurrence_rules WHERE id=(p_command->>'rule_id')::uuid FOR UPDATE;
  IF action='create' THEN
    IF r.id IS NOT NULL OR (p_command->>'expected_revision')::integer IS DISTINCT FROM 0 THEN RAISE EXCEPTION 'Rule already exists' USING ERRCODE='22023'; END IF;
    r.id:=(p_command->>'rule_id')::uuid;r.owner_id:=auth.uid();r.tab_id:=(p_command->>'p_tab_id')::uuid;
    r.anchor:=(p_command->>'anchor')::date;r.timezone:=p_command->>'timezone';r.revision:=1;r.status:='active';
  ELSE
    IF r.id IS NULL OR r.owner_id<>auth.uid() THEN RAISE EXCEPTION 'Rule not owned by caller' USING ERRCODE='42501'; END IF;
    IF r.revision IS DISTINCT FROM (p_command->>'expected_revision')::integer OR r.status='ended' THEN RAISE EXCEPTION 'Stale or ended rule' USING ERRCODE='22023'; END IF;
    IF (p_command ? 'anchor' AND (p_command->>'anchor')::date IS DISTINCT FROM r.anchor) OR
       (p_command ? 'timezone' AND p_command->>'timezone' IS DISTINCT FROM r.timezone) OR
       (p_command ? 'p_tab_id' AND (p_command->>'p_tab_id')::uuid IS DISTINCT FROM r.tab_id) THEN
      RAISE EXCEPTION 'Rule anchor, timezone and tab are immutable' USING ERRCODE='22023'; END IF;
    r.revision:=r.revision+1;
  END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=r.timezone) THEN RAISE EXCEPTION 'Unknown IANA timezone' USING ERRCODE='22023'; END IF;
  today:=(statement_timestamp() AT TIME ZONE r.timezone)::date;
  IF action IN ('create','edit') THEN
    r.unit:=p_command->>'unit';r.step:=(p_command->>'step')::integer;r.end_date:=(p_command->>'end_date')::date;
    r.template:=p_command->'template';
    IF (r.template ? 'p_expected_actor' AND (r.template->>'p_expected_actor')::uuid IS DISTINCT FROM r.owner_id) OR
      coalesce(r.template->>'p_receipt_url','')<>'' THEN RAISE EXCEPTION 'Rule cannot reuse receipts or another actor' USING ERRCODE='22023'; END IF;
    IF r.anchor IS NULL OR r.unit IS NULL OR r.unit NOT IN ('daily','weekly','monthly') OR r.step IS NULL OR r.step NOT BETWEEN 1 AND 120 OR
      (r.end_date IS NOT NULL AND r.end_date<r.anchor) OR r.template IS NULL OR
      (r.template->>'p_tab_id')::uuid IS DISTINCT FROM r.tab_id THEN RAISE EXCEPTION 'Invalid rule definition' USING ERRCODE='22023'; END IF;
    allocated:=public.allocate_custom_split_v1(r.template->'split',(r.template->>'p_paid_by_user_id')::uuid);
    IF (r.template->>'p_total_amount_centavos')::bigint IS DISTINCT FROM (allocated->>'total_centavos')::bigint OR
      r.template->'p_participants' IS DISTINCT FROM allocated->'participants' THEN RAISE EXCEPTION 'Rule allocation mismatch' USING ERRCODE='22023'; END IF;
    PERFORM public.validate_expense_roster_v2(r.tab_id,allocated->'participants',r.owner_id);
    r.effective_from:=greatest(r.anchor,today);r.next_index:=public.recurrence_index_v1(r.anchor,r.unit,r.step,r.effective_from);
  ELSIF action='pause' THEN r.status:='paused';
  ELSIF action='end' THEN r.status:='ended';
  ELSIF action='resume' THEN
    PERFORM public.validate_expense_roster_v2(r.tab_id,r.template->'p_participants',r.owner_id);
    r.status:='active';r.effective_from:=greatest(r.anchor,today);
    r.next_index:=public.recurrence_index_v1(r.anchor,r.unit,r.step,r.effective_from);
  END IF;
  IF action='create' THEN
    INSERT INTO public.recurrence_rules(id,owner_id,tab_id,anchor,timezone,unit,step,end_date,template,status,revision,effective_from,next_index)
      VALUES(r.id,r.owner_id,r.tab_id,r.anchor,r.timezone,r.unit,r.step,r.end_date,r.template,r.status,r.revision,r.effective_from,r.next_index);
  ELSE UPDATE public.recurrence_rules SET unit=r.unit,step=r.step,end_date=r.end_date,template=r.template,status=r.status,
    revision=r.revision,effective_from=r.effective_from,next_index=r.next_index WHERE id=r.id; END IF;
  INSERT INTO public.recurrence_events(rule_id,revision,action,snapshot) VALUES(r.id,r.revision,action,to_jsonb(r));
  RETURN public.record_m2_v1(p_operation_id,'m2_recurrence',p_command,r.id);
END $$;

-- The private writer is defined below. Only trusted routines can call it; it
-- validates the explicit rule owner and actual roster without setting JWT claims.
CREATE FUNCTION public.materialize_recurrence_internal_v1(p_rule uuid,p_date date,p_source text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE r public.recurrence_rules; result uuid; n integer; calculated jsonb; command jsonb;
BEGIN
  SELECT * INTO STRICT r FROM public.recurrence_rules WHERE id=p_rule FOR UPDATE;
  SELECT transaction_id INTO result FROM public.recurrence_occurrences WHERE rule_id=p_rule AND occurrence_date=p_date;
  IF result IS NOT NULL THEN
    IF p_date=public.recurrence_date_v1(r.anchor,r.unit,r.step,r.next_index) THEN
      UPDATE public.recurrence_rules SET next_index=r.next_index+1 WHERE id=r.id;
    END IF;
    RETURN result;
  END IF;
  n:=public.recurrence_index_v1(r.anchor,r.unit,r.step,p_date);
  IF p_date IS NULL OR r.status<>'active' OR p_date<r.effective_from OR
    (r.end_date IS NOT NULL AND p_date>r.end_date) OR public.recurrence_date_v1(r.anchor,r.unit,r.step,n)<>p_date OR
    (p_date::timestamp AT TIME ZONE r.timezone)>statement_timestamp() THEN
    RAISE EXCEPTION 'Occurrence not due or rule paused/ended' USING ERRCODE='22023'; END IF;
  calculated:=public.allocate_custom_split_v1(r.template->'split',(r.template->>'p_paid_by_user_id')::uuid);
  PERFORM public.validate_expense_roster_v2(r.tab_id,calculated->'participants',r.owner_id);
  result:=public.create_rule_expense_internal_v1(r.owner_id,r.tab_id,r.template->>'p_description',r.template->>'p_category',
    (calculated->>'total_centavos')::bigint,(r.template->>'p_paid_by_user_id')::uuid,calculated->'participants',p_date,NULL);
  INSERT INTO public.expense_split_details VALUES(result,(r.template->'split')||calculated,now());
  INSERT INTO public.recurrence_occurrences VALUES(r.id,p_date,result,r.revision,p_source,now());
  IF p_date=public.recurrence_date_v1(r.anchor,r.unit,r.step,r.next_index) THEN
    UPDATE public.recurrence_rules SET next_index=r.next_index+1 WHERE id=r.id;
  END IF;
  RETURN result;
END $$;
CREATE FUNCTION public.materialize_recurrence_v1(p_operation_id uuid,p_command jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE result uuid; r public.recurrence_rules;
BEGIN
  result:=public.require_m2_v1('recurring',p_operation_id,p_command,'m2_occurrence');IF result IS NOT NULL THEN RETURN result; END IF;
  SELECT * INTO r FROM public.recurrence_rules WHERE id=(p_command->>'rule_id')::uuid;
  IF r.id IS NULL OR r.owner_id<>auth.uid() THEN RAISE EXCEPTION 'Rule not owned' USING ERRCODE='42501'; END IF;
  result:=public.materialize_recurrence_internal_v1(r.id,(p_command->>'occurrence_date')::date,'owner');
  RETURN public.record_m2_v1(p_operation_id,'m2_occurrence',p_command,result);
END $$;
CREATE FUNCTION public.materialize_due_recurrences_v1(p_limit integer DEFAULT 25) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE r public.recurrence_rules; due_day date; count_created integer:=0; count_failed integer:=0;
BEGIN
  IF NOT coalesce((SELECT enabled FROM public.m2_feature_flags WHERE feature='recurring'),false) THEN RAISE EXCEPTION 'Feature awaiting acceptance' USING ERRCODE='42501'; END IF;
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'Invalid batch' USING ERRCODE='22023'; END IF;
  FOR r IN SELECT * FROM public.recurrence_rules WHERE status='active' AND
    (public.recurrence_date_v1(anchor,unit,step,next_index)::timestamp AT TIME ZONE timezone)<=statement_timestamp()
    ORDER BY (public.recurrence_date_v1(anchor,unit,step,next_index)::timestamp AT TIME ZONE timezone),id LIMIT p_limit FOR UPDATE SKIP LOCKED LOOP
    due_day:=public.recurrence_date_v1(r.anchor,r.unit,r.step,r.next_index);
    IF r.end_date IS NOT NULL AND due_day>r.end_date THEN UPDATE public.recurrence_rules SET status='ended' WHERE id=r.id;CONTINUE; END IF;
    BEGIN
      PERFORM public.materialize_recurrence_internal_v1(r.id,due_day,'scheduler');
      UPDATE public.recurrence_rules SET next_index=r.next_index+1 WHERE id=r.id;
      count_created:=count_created+1;
    EXCEPTION WHEN OTHERS THEN
      UPDATE public.recurrence_rules SET status='needs_attention' WHERE id=r.id;
      INSERT INTO public.recurrence_events(rule_id,revision,action,snapshot)
        VALUES(r.id,r.revision,'scheduler_failed',jsonb_build_object('code',SQLSTATE));
      count_failed:=count_failed+1;
    END;
  END LOOP;
  RETURN jsonb_build_object('processed',count_created,'needs_attention',count_failed);
END $$;
CREATE FUNCTION public.list_recurrences_v1(p_tab_id uuid,p_after uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE records jsonb; last_id uuid; more boolean;
BEGIN
  PERFORM public.tabby_pre_request();
  IF auth.uid() IS NULL OR NOT public.is_tab_member(p_tab_id,auth.uid()) THEN RAISE EXCEPTION 'Tab not authorized' USING ERRCODE='42501'; END IF;
  WITH window_rows AS (SELECT * FROM public.recurrence_rules WHERE owner_id=auth.uid() AND tab_id=p_tab_id
    AND (p_after IS NULL OR id>p_after) ORDER BY id LIMIT 51),page AS (SELECT * FROM window_rows ORDER BY id LIMIT 50)
  SELECT coalesce(jsonb_agg(to_jsonb(r)||jsonb_build_object('next_date',public.recurrence_date_v1(anchor,unit,step,next_index)) ORDER BY id),'[]'::jsonb),
    (SELECT id FROM page ORDER BY id DESC LIMIT 1),(SELECT count(*)>50 FROM window_rows) INTO records,last_id,more FROM page r;
  RETURN jsonb_build_object('account_id',auth.uid(),'tab_id',p_tab_id,'records',records,'next_cursor',CASE WHEN more THEN last_id ELSE NULL END);
END $$;
REVOKE ALL ON FUNCTION public.materialize_recurrence_internal_v1(uuid,date,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.change_recurrence_v1(uuid,jsonb),public.materialize_recurrence_v1(uuid,jsonb),public.list_recurrences_v1(uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.change_recurrence_v1(uuid,jsonb),public.materialize_recurrence_v1(uuid,jsonb),public.list_recurrences_v1(uuid,uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.materialize_due_recurrences_v1(integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.materialize_due_recurrences_v1(integer) TO service_role;
-- Private validated writer appended below.

CREATE FUNCTION public.create_rule_expense_internal_v1(
    p_actor UUID,
    p_tab_id UUID,
    p_description TEXT,
    p_category TEXT,
    p_total_amount_centavos BIGINT,
    p_paid_by_user_id UUID,
    p_participants JSONB,
    p_due_date DATE DEFAULT NULL,
    p_receipt_url TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_transaction_id UUID;
    v_participant JSONB;
    v_payer_count INTEGER := 0;
    v_share_total BIGINT := 0;
    v_user_id UUID;
    v_contact_id UUID;
    v_role TEXT;
    v_share BIGINT;
BEGIN
    PERFORM public.validate_expense_roster_v2(p_tab_id,p_participants,p_actor);
    IF p_actor IS NULL OR NOT public.is_tab_member(p_tab_id, p_actor) THEN
        RAISE EXCEPTION 'Not authorized to create an expense for this tab';
    END IF;
    IF p_total_amount_centavos IS NULL OR p_total_amount_centavos <= 0 THEN
        RAISE EXCEPTION 'Expense amount must be greater than zero';
    END IF;
    IF p_paid_by_user_id IS NULL
       OR (NOT public.is_tab_member(p_tab_id, p_paid_by_user_id) AND NOT EXISTS (
          SELECT 1 FROM public.contacts c JOIN public.tab_members tm ON tm.contact_id=c.id
          JOIN public.tabs t ON t.id=tm.tab_id
          WHERE c.id=p_paid_by_user_id AND c.owner_user_id=p_actor
            AND tm.tab_id=p_tab_id AND t.tab_type='individual')) THEN
        RAISE EXCEPTION 'Payer must be a member of the tab';
    END IF;
    IF jsonb_typeof(p_participants) <> 'array'
       OR jsonb_array_length(p_participants) = 0 THEN
        RAISE EXCEPTION 'At least one participant is required';
    END IF;

    FOR v_participant IN SELECT value FROM jsonb_array_elements(p_participants)
    LOOP
        v_user_id := NULLIF(v_participant->>'user_id', '')::UUID;
        v_contact_id := NULLIF(v_participant->>'contact_id', '')::UUID;
        v_role := COALESCE(v_participant->>'participant_role', 'debtor');
        v_share := COALESCE((v_participant->>'share_amount_centavos')::BIGINT, -1);

        IF (v_user_id IS NULL) = (v_contact_id IS NULL) THEN
            RAISE EXCEPTION 'Each participant must identify exactly one user or contact';
        END IF;
        IF v_share < 0 THEN
            RAISE EXCEPTION 'Participant share cannot be negative';
        END IF;
        IF v_role NOT IN ('payer', 'debtor', 'beneficiary') THEN
            RAISE EXCEPTION 'Invalid participant role';
        END IF;
        IF v_role = 'payer' THEN
            v_payer_count := v_payer_count + 1;
            IF COALESCE(v_user_id,v_contact_id) IS DISTINCT FROM p_paid_by_user_id THEN
                RAISE EXCEPTION 'Payer participant must match p_paid_by_user_id';
            END IF;
        END IF;
        IF v_user_id IS NOT NULL
           AND NOT public.is_tab_member(p_tab_id, v_user_id) THEN
            RAISE EXCEPTION 'User participant must be a member of the tab';
        END IF;
        IF v_contact_id IS NOT NULL
           AND NOT EXISTS (
               SELECT 1 FROM public.tab_members tm JOIN public.contacts c ON c.id=tm.contact_id
               JOIN public.tabs t ON t.id=tm.tab_id
               WHERE tm.tab_id=p_tab_id AND tm.contact_id=v_contact_id
                 AND c.owner_user_id=p_actor AND t.tab_type='individual'
           ) THEN
            RAISE EXCEPTION 'Contact participant must be a member of the tab';
        END IF;
        v_share_total := v_share_total + v_share;
    END LOOP;

    IF v_payer_count <> 1 THEN
        RAISE EXCEPTION 'Exactly one payer participant is required';
    END IF;
    IF v_share_total <> p_total_amount_centavos THEN
        RAISE EXCEPTION 'Participant shares must equal the total expense amount';
    END IF;

    INSERT INTO public.transactions (
        tab_id, created_by, transaction_type, category, description,
        total_amount_centavos, currency, status, due_date, receipt_url
    ) VALUES (
        p_tab_id, p_actor, 'shared_expense',
        COALESCE(NULLIF(trim(p_category), ''), 'other'),
        COALESCE(NULLIF(trim(p_description), ''), 'Expense'),
        p_total_amount_centavos, 'PHP', 'acknowledged',
        p_due_date, p_receipt_url
    )
    RETURNING id INTO v_transaction_id;

    INSERT INTO public.transaction_participants (
        transaction_id, user_id, contact_id, participant_role,
        share_amount_centavos, acknowledged
    )
    SELECT
        v_transaction_id,
        NULLIF(value->>'user_id', '')::UUID,
        NULLIF(value->>'contact_id', '')::UUID,
        COALESCE(value->>'participant_role', 'debtor'),
        (value->>'share_amount_centavos')::BIGINT,
        COALESCE((value->>'acknowledged')::BOOLEAN, false)
    FROM jsonb_array_elements(p_participants);

    RETURN v_transaction_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public;



REVOKE ALL ON FUNCTION public.create_rule_expense_internal_v1(uuid,uuid,text,text,bigint,uuid,jsonb,date,text) FROM PUBLIC,anon,authenticated;

-- Retire private scheduling state during the existing reviewed privacy flow.
ALTER FUNCTION public.prepare_account_deletion_v1(uuid) RENAME TO prepare_account_deletion_core_v1;
REVOKE ALL ON FUNCTION public.prepare_account_deletion_core_v1(uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.prepare_account_deletion_v1(p_request_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE result jsonb; actor uuid;
BEGIN
  SELECT user_id INTO STRICT actor FROM public.account_deletion_requests WHERE id=p_request_id;
  PERFORM pg_advisory_xact_lock(hashtextextended('account-lifecycle:'||actor::text,0));
  PERFORM id FROM public.recurrence_rules WHERE owner_id=actor ORDER BY id FOR UPDATE;
  result:=public.prepare_account_deletion_core_v1(p_request_id);
  UPDATE public.recurrence_events SET snapshot=jsonb_build_object('redacted',true,'revision',revision)
    WHERE rule_id IN (SELECT id FROM public.recurrence_rules WHERE owner_id=actor);
  UPDATE public.recurrence_rules SET status='ended',template='{}'::jsonb WHERE owner_id=actor;
  RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.prepare_account_deletion_v1(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_account_deletion_v1(uuid) TO service_role;
CREATE FUNCTION public.get_expense_split_v1(p_transaction_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE result jsonb;
BEGIN
  PERFORM public.tabby_pre_request();
  IF NOT public.can_read_expense_split_v1(p_transaction_id) THEN RAISE EXCEPTION 'Expense not authorized' USING ERRCODE='42501'; END IF;
  SELECT breakdown INTO result FROM public.expense_split_details WHERE transaction_id=p_transaction_id;
  RETURN jsonb_build_object('account_id',auth.uid(),'transaction_id',p_transaction_id,'breakdown',result);
END $$;
REVOKE ALL ON FUNCTION public.get_expense_split_v1(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_expense_split_v1(uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.protect_profile_identity_v1() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  IF TG_OP='UPDATE' AND OLD.anonymized_at IS NOT NULL AND current_setting('role',true) IN ('anon','authenticated') THEN
    RAISE EXCEPTION 'Account no longer active' USING ERRCODE='42501';
  END IF;
  IF TG_OP='UPDATE' AND OLD.anonymized_at IS NOT NULL THEN NEW.anonymized_at:=OLD.anonymized_at; END IF;
  IF NEW.anonymized_at IS NOT NULL AND current_setting('role',true) NOT IN ('anon','authenticated') THEN
    -- Auth's profile-upsert trigger must not restore PII during soft deletion.
    NEW.display_name:='Former member'; NEW.email:=NULL; NEW.phone:=NULL; NEW.avatar_url:=NULL;
    NEW.gcash_number:=NULL; NEW.maya_number:=NULL; NEW.qr_code_url:=NULL;
    RETURN NEW;
  END IF;
  IF NEW.email IS DISTINCT FROM (CASE WHEN TG_OP='UPDATE' THEN OLD.email ELSE NULL END)
     AND NEW.email IS DISTINCT FROM (SELECT email FROM auth.users WHERE id=NEW.id) THEN
    RAISE EXCEPTION 'Profile email must match Auth' USING ERRCODE='42501';
  END IF;
  IF current_setting('role',true) IN ('anon','authenticated') THEN
    IF TG_OP='INSERT' THEN
      IF coalesce(NEW.gcash_number,'')<>'' OR coalesce(NEW.maya_number,'')<>'' OR coalesce(NEW.qr_code_url,'')<>'' THEN
        RAISE EXCEPTION 'Use saved receiving methods' USING ERRCODE='42501'; END IF;
    ELSIF NEW.gcash_number IS DISTINCT FROM OLD.gcash_number OR NEW.maya_number IS DISTINCT FROM OLD.maya_number
      OR NEW.qr_code_url IS DISTINCT FROM OLD.qr_code_url THEN
      RAISE EXCEPTION 'Use saved receiving methods' USING ERRCODE='42501';
    END IF;
  END IF;
  RETURN NEW;
END $$;


COMMIT;

-- M2 explicit contact claiming (rollout disabled)
BEGIN;
CREATE TABLE public.contact_claim_invitations(
 id uuid PRIMARY KEY,owner_id uuid NOT NULL REFERENCES public.users(id),target_id uuid NOT NULL REFERENCES public.users(id),
 contact_id uuid NOT NULL REFERENCES public.contacts(id),source_tab_id uuid NOT NULL REFERENCES public.tabs(id),
 snapshot jsonb NOT NULL,status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','declined','accepted','superseded')),
 destination_tab_id uuid REFERENCES public.tabs(id),reverse_id uuid REFERENCES public.transactions(id),transfer_id uuid REFERENCES public.transactions(id),
 created_at timestamptz NOT NULL DEFAULT now(),decided_at timestamptz,CHECK(owner_id<>target_id));
CREATE UNIQUE INDEX ON public.contact_claim_invitations(contact_id) WHERE status='pending';
ALTER TABLE public.contact_claim_invitations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.contact_claim_invitations FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.claim_contact(uuid,uuid) FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.claim_source_snapshot_v1(p_contact uuid,p_owner uuid,p_tab uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE financial jsonb;n bigint;count_rows integer;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.contacts WHERE id=p_contact AND owner_user_id=p_owner AND claimed_user_id IS NULL AND claim_status='unclaimed') OR
   NOT EXISTS(SELECT 1 FROM public.tabs WHERE id=p_tab AND user_a=p_owner AND user_b IS NULL AND tab_type='individual' AND status='active') OR
   (SELECT count(*) FROM public.tab_members WHERE contact_id=p_contact)<>1 OR
   NOT EXISTS(SELECT 1 FROM public.tab_members WHERE tab_id=p_tab AND contact_id=p_contact) OR
   EXISTS(SELECT 1 FROM public.tab_members WHERE tab_id=p_tab AND (user_id IS DISTINCT FROM p_owner AND contact_id IS DISTINCT FROM p_contact)) THEN
   RAISE EXCEPTION 'Ambiguous or unavailable contact relationship' USING ERRCODE='22023'; END IF;
 IF EXISTS(SELECT 1 FROM public.payments WHERE tab_id=p_tab AND status='submitted') OR
    EXISTS(SELECT 1 FROM public.expense_change_requests r JOIN public.transactions t ON t.id=r.transaction_id WHERE t.tab_id=p_tab AND NOT EXISTS(SELECT 1 FROM public.expense_change_results WHERE change_id=r.id) AND NOT EXISTS(SELECT 1 FROM public.expense_change_decisions WHERE change_id=r.id AND NOT accepted)) THEN
   RAISE EXCEPTION 'Resolve pending financial decisions first' USING ERRCODE='22023'; END IF;
 SELECT count(*) INTO count_rows FROM public.transactions WHERE tab_id=p_tab;
 IF count_rows>5000 THEN RAISE EXCEPTION 'Contact history requires reconciliation' USING ERRCODE='22023'; END IF;
 SELECT jsonb_build_object('expenses',coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.id) FROM public.transactions t WHERE tab_id=p_tab),'[]'),
 'shares',coalesce((SELECT jsonb_agg(to_jsonb(s) ORDER BY s.id) FROM public.transaction_participants s JOIN public.transactions t ON t.id=s.transaction_id WHERE t.tab_id=p_tab),'[]'),
 'payments',coalesce((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.id) FROM public.payments p WHERE tab_id=p_tab),'[]')) INTO financial;
 n:=public.get_party_outstanding_internal(p_tab,'contact',p_contact,'user',p_owner)-public.get_party_outstanding_internal(p_tab,'user',p_owner,'contact',p_contact);
 IF abs(n)>99999999999 THEN RAISE EXCEPTION 'Net balance requires explicit reconciliation' USING ERRCODE='22023';END IF;
 RETURN jsonb_build_object('digest',md5(financial::text),'owner_net_centavos',n,'expense_count',count_rows);
END $$;
REVOKE ALL ON FUNCTION public.claim_source_snapshot_v1(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.invite_contact_claim_v1(p_operation_id uuid,p_command jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE result uuid;c public.contacts;snapshot jsonb;target uuid:=(p_command->>'target_id')::uuid;tab uuid:=(p_command->>'source_tab_id')::uuid;
BEGIN
 result:=public.require_m2_v1('contact_claiming',p_operation_id,p_command,'m2_claim_invite');IF result IS NOT NULL THEN RETURN result;END IF;
 IF p_command-ARRAY['p_expected_actor','claim_id','contact_id','target_id','source_tab_id','snapshot_digest']<>'{}' THEN RAISE EXCEPTION 'Unsupported claim fields' USING ERRCODE='22023';END IF;
 LOCK TABLE public.transactions,public.transaction_participants,public.payments IN SHARE ROW EXCLUSIVE MODE;
 SELECT * INTO c FROM public.contacts WHERE id=(p_command->>'contact_id')::uuid FOR UPDATE;
 IF EXISTS(SELECT 1 FROM public.friendships WHERE status='blocked' AND least(requester_id,addressee_id)=least(auth.uid(),target) AND greatest(requester_id,addressee_id)=greatest(auth.uid(),target)) THEN RAISE EXCEPTION 'Relationship unavailable' USING ERRCODE='42501';END IF;
 IF c.owner_user_id IS DISTINCT FROM auth.uid() OR target=auth.uid() OR NOT EXISTS(SELECT 1 FROM public.users WHERE id=target AND anonymized_at IS NULL) THEN RAISE EXCEPTION 'Claim not authorized' USING ERRCODE='42501';END IF;
 snapshot:=public.claim_source_snapshot_v1(c.id,auth.uid(),tab);
 IF snapshot->>'digest' IS DISTINCT FROM p_command->>'snapshot_digest' THEN RAISE EXCEPTION 'Refresh contact history before inviting' USING ERRCODE='40001';END IF;
 UPDATE public.contact_claim_invitations SET status='superseded',decided_at=now() WHERE contact_id=c.id AND status='pending';
 INSERT INTO public.contact_claim_invitations(id,owner_id,target_id,contact_id,source_tab_id,snapshot)
 VALUES((p_command->>'claim_id')::uuid,auth.uid(),target,c.id,tab,snapshot) RETURNING id INTO result;
 RETURN public.record_m2_v1(p_operation_id,'m2_claim_invite',p_command,result);
END $$;
CREATE FUNCTION public.decide_contact_claim_v1(p_operation_id uuid,p_command jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE result uuid;c public.contact_claim_invitations;snapshot jsonb;net bigint;dest uuid;v_reverse uuid;v_transfer uuid;parts jsonb;
BEGIN
 result:=public.require_m2_v1('contact_claiming',p_operation_id,p_command,'m2_claim_decide');IF result IS NOT NULL THEN RETURN result;END IF;
 IF p_command-ARRAY['p_expected_actor','claim_id','accept','snapshot_digest']<>'{}' OR jsonb_typeof(p_command->'accept') IS DISTINCT FROM 'boolean' THEN RAISE EXCEPTION 'Explicit decision required' USING ERRCODE='22023';END IF;
 -- Same order as invitation and before any claim/contact rows. Legacy financial
 -- writers do not take claim locks: these short table locks freeze their DML.
 LOCK TABLE public.transactions,public.transaction_participants,public.payments IN SHARE ROW EXCLUSIVE MODE;
 SELECT * INTO c FROM public.contact_claim_invitations WHERE id=(p_command->>'claim_id')::uuid FOR UPDATE;
 IF c.id IS NULL OR c.target_id<>auth.uid() THEN RAISE EXCEPTION 'Only the invited account can decide' USING ERRCODE='42501';END IF;
 IF c.status IN ('accepted','declined') THEN
  IF (c.status='accepted') IS DISTINCT FROM (p_command->>'accept')::boolean OR c.snapshot->>'digest' IS DISTINCT FROM p_command->>'snapshot_digest' THEN RAISE EXCEPTION 'Decision conflict' USING ERRCODE='22023';END IF;
  RETURN public.record_m2_v1(p_operation_id,'m2_claim_decide',p_command,c.id);
 END IF;
 IF c.status<>'pending' OR c.snapshot->>'digest' IS DISTINCT FROM p_command->>'snapshot_digest' THEN RAISE EXCEPTION 'Invitation is stale' USING ERRCODE='40001';END IF;
 IF NOT (p_command->>'accept')::boolean THEN
  UPDATE public.contact_claim_invitations SET status='declined',decided_at=now() WHERE id=c.id;
  RETURN public.record_m2_v1(p_operation_id,'m2_claim_decide',p_command,c.id);
 END IF;
 PERFORM 1 FROM public.contacts WHERE id=c.contact_id FOR UPDATE;
 snapshot:=public.claim_source_snapshot_v1(c.contact_id,c.owner_id,c.source_tab_id);
 IF snapshot IS DISTINCT FROM c.snapshot THEN RAISE EXCEPTION 'History changed; request a fresh invitation' USING ERRCODE='40001';END IF;
 IF EXISTS(SELECT 1 FROM public.users WHERE id IN (c.owner_id,c.target_id) AND anonymized_at IS NOT NULL) THEN RAISE EXCEPTION 'Account inactive' USING ERRCODE='42501';END IF;
 net:=(snapshot->>'owner_net_centavos')::bigint;
 INSERT INTO public.tabs(user_a,user_b) VALUES(least(c.owner_id,c.target_id),greatest(c.owner_id,c.target_id)) ON CONFLICT DO NOTHING;
 SELECT id INTO STRICT dest FROM public.tabs WHERE tab_type='individual' AND status='active' AND least(user_a,user_b)=least(c.owner_id,c.target_id) AND greatest(user_a,user_b)=greatest(c.owner_id,c.target_id);
 INSERT INTO public.tab_members(tab_id,user_id) VALUES(dest,c.owner_id),(dest,c.target_id) ON CONFLICT DO NOTHING;
 IF net<>0 THEN
  parts:=jsonb_build_array(jsonb_build_object('user_id',c.owner_id,'participant_role',CASE WHEN net>0 THEN 'debtor' ELSE 'payer' END,'share_amount_centavos',CASE WHEN net>0 THEN abs(net) ELSE 0 END,'acknowledged',false),
   jsonb_build_object('contact_id',c.contact_id,'participant_role',CASE WHEN net>0 THEN 'payer' ELSE 'debtor' END,'share_amount_centavos',CASE WHEN net>0 THEN 0 ELSE abs(net) END,'acknowledged',false));
  v_reverse:=public.create_rule_expense_internal_v1(c.owner_id,c.source_tab_id,'Contact claim offset '||c.id,'other',abs(net),CASE WHEN net>0 THEN c.contact_id ELSE c.owner_id END,parts,NULL,NULL);
  parts:=jsonb_build_array(jsonb_build_object('user_id',c.owner_id,'participant_role',CASE WHEN net>0 THEN 'payer' ELSE 'debtor' END,'share_amount_centavos',CASE WHEN net>0 THEN 0 ELSE abs(net) END,'acknowledged',false),
   jsonb_build_object('user_id',c.target_id,'participant_role',CASE WHEN net>0 THEN 'debtor' ELSE 'payer' END,'share_amount_centavos',CASE WHEN net>0 THEN abs(net) ELSE 0 END,'acknowledged',false));
  v_transfer:=public.create_rule_expense_internal_v1(c.owner_id,dest,'Accepted contact claim '||c.id,'other',abs(net),CASE WHEN net>0 THEN c.owner_id ELSE c.target_id END,parts,NULL,NULL);
 END IF;
 UPDATE public.contact_claim_invitations SET status='accepted',destination_tab_id=dest,reverse_id=v_reverse,transfer_id=v_transfer,decided_at=now() WHERE id=c.id;
 UPDATE public.contacts SET claimed_user_id=c.target_id,claim_status='claimed',claimed_at=now() WHERE id=c.contact_id;
 UPDATE public.tabs SET status='archived' WHERE id=c.source_tab_id;
 RETURN public.record_m2_v1(p_operation_id,'m2_claim_decide',p_command,c.id);
END $$;
CREATE FUNCTION public.guard_contact_claim_identity_v1() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
 IF TG_OP='INSERT' THEN
 IF NEW.claimed_user_id IS NOT NULL OR NEW.claim_status<>'unclaimed' OR NEW.claimed_at IS NOT NULL THEN RAISE EXCEPTION 'New contacts must be unclaimed' USING ERRCODE='42501';END IF;RETURN NEW;END IF;
 IF NEW.owner_user_id IS DISTINCT FROM OLD.owner_user_id THEN RAISE EXCEPTION 'Contact owner is immutable' USING ERRCODE='42501';END IF;
 IF (NEW.claimed_user_id,NEW.claim_status,NEW.claimed_at) IS DISTINCT FROM (OLD.claimed_user_id,OLD.claim_status,OLD.claimed_at) AND
 NOT EXISTS(SELECT 1 FROM public.contact_claim_invitations WHERE contact_id=NEW.id AND status='accepted' AND target_id=NEW.claimed_user_id AND NEW.claim_status='claimed' AND OLD.claimed_user_id IS NULL) THEN
 RAISE EXCEPTION 'Use explicit consent flow' USING ERRCODE='42501';END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER protect_contact_claim BEFORE INSERT OR UPDATE ON public.contacts FOR EACH ROW EXECUTE FUNCTION public.guard_contact_claim_identity_v1();
CREATE FUNCTION public.guard_claimed_source_v1() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM public.contact_claim_invitations WHERE source_tab_id=NEW.tab_id AND status='accepted') THEN RAISE EXCEPTION 'Claimed source history is closed' USING ERRCODE='42501';END IF;RETURN NEW;
END $$;
CREATE TRIGGER closed_claim_transactions BEFORE INSERT ON public.transactions FOR EACH ROW EXECUTE FUNCTION public.guard_claimed_source_v1();
CREATE TRIGGER closed_claim_payments BEFORE INSERT ON public.payments FOR EACH ROW EXECUTE FUNCTION public.guard_claimed_source_v1();
-- Retained contact participants are never rewritten to a registered UUID.
CREATE OR REPLACE FUNCTION public.is_tab_member(p_tab_id uuid,p_user_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
 SELECT public.account_is_active_v1() AND p_user_id IS NOT NULL AND (
 EXISTS(SELECT 1 FROM public.tab_members WHERE tab_id=p_tab_id AND user_id=p_user_id) OR
 EXISTS(SELECT 1 FROM public.tabs WHERE id=p_tab_id AND (user_a=p_user_id OR user_b=p_user_id)) OR
 EXISTS(SELECT 1 FROM public.tabs t JOIN public.group_members gm ON gm.group_id=t.group_id WHERE t.id=p_tab_id AND gm.user_id=p_user_id AND gm.status='active') OR
 EXISTS(SELECT 1 FROM public.contact_claim_invitations WHERE source_tab_id=p_tab_id AND target_id=p_user_id AND status='accepted'));
$$;
CREATE FUNCTION public.find_claim_target_v1(p_friend_code text) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE target jsonb;
BEGIN
 PERFORM public.tabby_pre_request();IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='42501';END IF;
 -- Reuse existing anti-enumeration/blocklist and exact friend-code lookup.
 SELECT jsonb_build_object('id',id,'display_name',display_name,'friend_code',friend_code) INTO target FROM public.find_user_by_friend_code(p_friend_code);
 RETURN jsonb_build_object('account_id',auth.uid(),'target',target);
END $$;
CREATE FUNCTION public.contact_claim_preview_v1(p_contact_id uuid,p_source_tab_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
 PERFORM public.tabby_pre_request();IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='42501';END IF;
 RETURN jsonb_build_object('account_id',auth.uid(),'contact_id',p_contact_id,'source_tab_id',p_source_tab_id,'snapshot',public.claim_source_snapshot_v1(p_contact_id,auth.uid(),p_source_tab_id));
END $$;
CREATE FUNCTION public.list_contact_claims_v1(p_after uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE records jsonb;last_id uuid;more boolean;
BEGIN
 PERFORM public.tabby_pre_request();IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='42501';END IF;
 WITH window_rows AS (SELECT * FROM public.contact_claim_invitations WHERE (owner_id=auth.uid() OR target_id=auth.uid()) AND (p_after IS NULL OR id>p_after) ORDER BY id LIMIT 51),page AS (SELECT * FROM window_rows ORDER BY id LIMIT 50)
 SELECT coalesce(jsonb_agg(to_jsonb(p) ORDER BY id),'[]'),(SELECT id FROM page ORDER BY id DESC LIMIT 1),(SELECT count(*)>50 FROM window_rows) INTO records,last_id,more FROM page p;
 RETURN jsonb_build_object('account_id',auth.uid(),'records',records,'next_cursor',CASE WHEN more THEN last_id ELSE NULL END);
END $$;
CREATE FUNCTION public.contact_claim_history_page_v1(p_claim_id uuid,p_after uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE c public.contact_claim_invitations;records jsonb;last_id uuid;more boolean;
BEGIN
 PERFORM public.tabby_pre_request();SELECT * INTO c FROM public.contact_claim_invitations WHERE id=p_claim_id;
 IF auth.uid() IS NULL OR c.id IS NULL OR NOT(auth.uid()=c.owner_id OR (auth.uid()=c.target_id AND c.status IN ('pending','accepted'))) THEN RAISE EXCEPTION 'History not authorized' USING ERRCODE='42501';END IF;
 WITH window_rows AS (SELECT t.id,t.description,t.total_amount_centavos,t.created_at,t.status,
 (SELECT jsonb_agg(jsonb_build_object('party',jsonb_build_object('kind',CASE WHEN s.contact_id IS NULL THEN 'user' ELSE 'contact' END,'id',coalesce(s.user_id,s.contact_id)),'role',s.participant_role,'share_centavos',s.share_amount_centavos) ORDER BY s.id) FROM public.transaction_participants s WHERE s.transaction_id=t.id) participants
 FROM public.transactions t WHERE t.tab_id=c.source_tab_id AND (p_after IS NULL OR t.id>p_after) ORDER BY t.id LIMIT 51),page AS(SELECT * FROM window_rows ORDER BY id LIMIT 50)
 SELECT coalesce(jsonb_agg(to_jsonb(p) ORDER BY id),'[]'),(SELECT id FROM page ORDER BY id DESC LIMIT 1),(SELECT count(*)>50 FROM window_rows) INTO records,last_id,more FROM page p;
 RETURN jsonb_build_object('account_id',auth.uid(),'claim_id',c.id,'records',records,'next_cursor',CASE WHEN more THEN last_id ELSE NULL END);
END $$;
REVOKE ALL ON FUNCTION public.invite_contact_claim_v1(uuid,jsonb),public.decide_contact_claim_v1(uuid,jsonb),public.find_claim_target_v1(text),public.contact_claim_preview_v1(uuid,uuid),public.list_contact_claims_v1(uuid),public.contact_claim_history_page_v1(uuid,uuid),public.guard_contact_claim_identity_v1(),public.guard_claimed_source_v1() FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.guard_contact_claim_identity_v1(),public.guard_claimed_source_v1() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.invite_contact_claim_v1(uuid,jsonb),public.decide_contact_claim_v1(uuid,jsonb),public.find_claim_target_v1(text),public.contact_claim_preview_v1(uuid,uuid),public.list_contact_claims_v1(uuid),public.contact_claim_history_page_v1(uuid,uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.protect_shared_archive_v1() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
 IF NEW.status IS DISTINCT FROM OLD.status AND (NEW.status='archived' OR OLD.status='archived') AND current_setting('role',true) IN ('anon','authenticated') AND
 NOT (OLD.status='active' AND NEW.status='archived' AND EXISTS(SELECT 1 FROM public.contact_claim_invitations WHERE source_tab_id=NEW.id AND status='accepted')) THEN
 RAISE EXCEPTION 'Use private Connections archive' USING ERRCODE='42501';END IF;RETURN NEW;
END $$;
CREATE FUNCTION public.contact_claim_payments_page_v1(p_claim_id uuid,p_after uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE c public.contact_claim_invitations;records jsonb;last_id uuid;more boolean;
BEGIN
 PERFORM public.tabby_pre_request();SELECT * INTO c FROM public.contact_claim_invitations WHERE id=p_claim_id;
 IF auth.uid() IS NULL OR c.id IS NULL OR NOT(auth.uid()=c.owner_id OR (auth.uid()=c.target_id AND c.status IN ('pending','accepted'))) THEN RAISE EXCEPTION 'History not authorized' USING ERRCODE='42501';END IF;
 WITH window_rows AS (SELECT id,amount_centavos,status,created_at,payer_user_id,payer_contact_id,recipient_user_id,recipient_contact_id FROM public.payments WHERE tab_id=c.source_tab_id AND (p_after IS NULL OR id>p_after) ORDER BY id LIMIT 51),page AS(SELECT * FROM window_rows ORDER BY id LIMIT 50)
 SELECT coalesce(jsonb_agg(to_jsonb(p) ORDER BY id),'[]'),(SELECT id FROM page ORDER BY id DESC LIMIT 1),(SELECT count(*)>50 FROM window_rows) INTO records,last_id,more FROM page p;
 RETURN jsonb_build_object('account_id',auth.uid(),'claim_id',c.id,'records',records,'next_cursor',CASE WHEN more THEN last_id ELSE NULL END);
END $$;
REVOKE ALL ON FUNCTION public.contact_claim_payments_page_v1(uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.contact_claim_payments_page_v1(uuid,uuid) TO authenticated;

CREATE FUNCTION public.guard_claimed_participants_v1() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM public.transactions t JOIN public.contact_claim_invitations c ON c.source_tab_id=t.tab_id WHERE t.id=NEW.transaction_id AND c.status='accepted') THEN RAISE EXCEPTION 'Claimed source history is closed' USING ERRCODE='42501';END IF;RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.guard_claimed_participants_v1() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER closed_claim_participants BEFORE INSERT ON public.transaction_participants FOR EACH ROW EXECUTE FUNCTION public.guard_claimed_participants_v1();
COMMIT;
-- M2 expense review (rollout disabled)
BEGIN;
-- Rollout rollback denies new intents, while exact recorded replays still recover.
CREATE OR REPLACE FUNCTION public.require_m2_v1(p_feature text,p_operation uuid,p_command jsonb,p_kind text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor uuid:=auth.uid(); prior public.financial_operations;
BEGIN
  IF actor IS NOT NULL THEN PERFORM pg_advisory_xact_lock(hashtextextended('account-lifecycle:'||actor::text,0)); END IF;
  PERFORM public.tabby_pre_request();
  IF actor IS NULL OR actor IS DISTINCT FROM (p_command->>'p_expected_actor')::uuid THEN
    RAISE EXCEPTION 'Account changed' USING ERRCODE='42501'; END IF;
  IF p_operation IS NULL OR p_command IS NULL OR jsonb_typeof(p_command)<>'object' THEN
    RAISE EXCEPTION 'Operation and command required' USING ERRCODE='22023'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':'||p_operation::text,0));
  SELECT * INTO prior FROM public.financial_operations WHERE actor_id=actor AND operation_id=p_operation;
  IF FOUND THEN
    IF prior.command_kind<>p_kind OR prior.command IS DISTINCT FROM p_command THEN
      RAISE EXCEPTION 'Operation payload conflict' USING ERRCODE='22023'; END IF;
    RETURN prior.result_id;
  END IF;
  IF NOT coalesce((SELECT enabled FROM public.m2_feature_flags WHERE feature=p_feature),false) THEN
    RAISE EXCEPTION 'Feature awaiting acceptance' USING ERRCODE='42501'; END IF;
  RETURN NULL;
END $$;

CREATE TABLE public.expense_acknowledgments(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),transaction_id uuid NOT NULL REFERENCES public.transactions(id),actor_id uuid NOT NULL REFERENCES public.users(id),created_at timestamptz NOT NULL DEFAULT now(),UNIQUE(transaction_id,actor_id));
CREATE TABLE public.expense_disputes(id uuid PRIMARY KEY,transaction_id uuid NOT NULL REFERENCES public.transactions(id),opened_by uuid NOT NULL REFERENCES public.users(id),reason text NOT NULL CHECK(length(trim(reason)) BETWEEN 1 AND 500),required_parties uuid[] NOT NULL,status text NOT NULL DEFAULT 'open' CHECK(status IN ('open','resolved')),resolution_id uuid,resolved_at timestamptz,created_at timestamptz NOT NULL DEFAULT now());
CREATE UNIQUE INDEX ON public.expense_disputes(transaction_id) WHERE status='open';
CREATE TABLE public.expense_dispute_resolutions(id uuid PRIMARY KEY,dispute_id uuid NOT NULL REFERENCES public.expense_disputes(id),proposed_by uuid NOT NULL REFERENCES public.users(id),resolution text NOT NULL CHECK(length(trim(resolution)) BETWEEN 1 AND 500),status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','rejected','agreed')),created_at timestamptz NOT NULL DEFAULT now());
CREATE UNIQUE INDEX ON public.expense_dispute_resolutions(dispute_id) WHERE status='pending';
CREATE TABLE public.expense_resolution_votes(resolution_id uuid NOT NULL REFERENCES public.expense_dispute_resolutions(id),actor_id uuid NOT NULL REFERENCES public.users(id),accepted boolean NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),PRIMARY KEY(resolution_id,actor_id));
ALTER TABLE public.expense_acknowledgments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expense_disputes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expense_dispute_resolutions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expense_resolution_votes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.expense_acknowledgments,public.expense_disputes,public.expense_dispute_resolutions,public.expense_resolution_votes FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.review_expense_v1(p_operation_id uuid,p_command jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE result uuid;expense public.transactions;d public.expense_disputes;r public.expense_dispute_resolutions;
 actor uuid:=auth.uid();action text:=p_command->>'action';parties uuid[];previous boolean;context jsonb;
BEGIN
 result:=public.require_m2_v1('expense_review',p_operation_id,p_command,'m2_review');IF result IS NOT NULL THEN RETURN result;END IF;
 IF action IS NULL OR action NOT IN ('acknowledge','propose','decide_proposal','open_dispute','propose_resolution','vote_resolution') THEN RAISE EXCEPTION 'Invalid review action' USING ERRCODE='22023';END IF;
 IF p_command-ARRAY['p_expected_actor','transaction_id','action','kind','new_total_centavos','reason','change_id','accept','dispute_id','resolution_id','resolution']<>'{}' THEN RAISE EXCEPTION 'Unsupported review fields' USING ERRCODE='22023';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended((p_command->>'transaction_id'),1));
 SELECT * INTO expense FROM public.transactions WHERE id=(p_command->>'transaction_id')::uuid;
 context:=public.expense_change_context_internal(expense.id,actor);
 IF expense.id IS NULL OR context IS NULL OR coalesce((context->>'manual_contact')::boolean,true) OR
 EXISTS(SELECT 1 FROM public.transaction_participants s JOIN public.users u ON u.id=s.user_id WHERE s.transaction_id=expense.id AND u.anonymized_at IS NOT NULL) THEN RAISE EXCEPTION 'Active registered expense parties required' USING ERRCODE='42501';END IF;
 SELECT array_agg(DISTINCT user_id ORDER BY user_id) INTO parties FROM public.transaction_participants WHERE transaction_id=expense.id;
 IF action='acknowledge' THEN
  IF actor=expense.created_by THEN RAISE EXCEPTION 'Creator cannot self-acknowledge' USING ERRCODE='42501';END IF;
  INSERT INTO public.expense_acknowledgments(transaction_id,actor_id) VALUES(expense.id,actor) ON CONFLICT DO NOTHING;
  SELECT id INTO result FROM public.expense_acknowledgments WHERE transaction_id=expense.id AND actor_id=actor;
 ELSIF action='propose' THEN
  -- A distinct deterministic inner operation preserves CAP-006's public replay
  -- contract. The outer operation records the exact M2 intent in the same registry.
  result:=public.request_expense_change_v2(md5('m2-proposal:'||actor::text||':'||p_operation_id::text)::uuid,expense.id,p_command->>'kind',(p_command->>'new_total_centavos')::bigint,p_command->>'reason',actor,false);
 ELSIF action='decide_proposal' THEN
  IF jsonb_typeof(p_command->'accept') IS DISTINCT FROM 'boolean' OR NOT EXISTS(SELECT 1 FROM public.expense_change_requests WHERE id=(p_command->>'change_id')::uuid AND transaction_id=expense.id) THEN RAISE EXCEPTION 'Proposal/decision mismatch' USING ERRCODE='22023';END IF;
  result:=public.decide_expense_change_v1((p_command->>'change_id')::uuid,(p_command->>'accept')::boolean,actor);
 ELSIF action='open_dispute' THEN
  IF cardinality(parties)<2 OR length(trim(coalesce(p_command->>'reason',''))) NOT BETWEEN 1 AND 500 THEN RAISE EXCEPTION 'Reason and affected parties required' USING ERRCODE='22023';END IF;
  INSERT INTO public.expense_disputes(id,transaction_id,opened_by,reason,required_parties) VALUES((p_command->>'dispute_id')::uuid,expense.id,actor,p_command->>'reason',parties) RETURNING id INTO result;
 ELSE
  SELECT * INTO d FROM public.expense_disputes WHERE id=(p_command->>'dispute_id')::uuid AND transaction_id=expense.id FOR UPDATE;
  IF d.id IS NULL OR NOT actor=ANY(d.required_parties) THEN RAISE EXCEPTION 'Dispute party required' USING ERRCODE='42501';END IF;
  IF action='propose_resolution' THEN
   IF d.status<>'open' OR length(trim(coalesce(p_command->>'resolution',''))) NOT BETWEEN 1 AND 500 THEN RAISE EXCEPTION 'Open dispute and resolution required' USING ERRCODE='22023';END IF;
   INSERT INTO public.expense_dispute_resolutions(id,dispute_id,proposed_by,resolution) VALUES((p_command->>'resolution_id')::uuid,d.id,actor,p_command->>'resolution') RETURNING id INTO result;
   INSERT INTO public.expense_resolution_votes VALUES(result,actor,true,now());
  ELSE
   SELECT * INTO r FROM public.expense_dispute_resolutions WHERE id=(p_command->>'resolution_id')::uuid AND dispute_id=d.id FOR UPDATE;
   IF r.id IS NULL OR jsonb_typeof(p_command->'accept') IS DISTINCT FROM 'boolean' THEN RAISE EXCEPTION 'Resolution and explicit vote required' USING ERRCODE='22023';END IF;
   SELECT accepted INTO previous FROM public.expense_resolution_votes WHERE resolution_id=r.id AND actor_id=actor;
   IF FOUND THEN
    IF previous IS DISTINCT FROM (p_command->>'accept')::boolean THEN RAISE EXCEPTION 'Vote conflict' USING ERRCODE='22023';END IF;
   ELSE
    IF d.status<>'open' OR r.status<>'pending' THEN RAISE EXCEPTION 'Resolution already decided' USING ERRCODE='22023';END IF;
    INSERT INTO public.expense_resolution_votes VALUES(r.id,actor,(p_command->>'accept')::boolean,now());
    IF NOT (p_command->>'accept')::boolean THEN UPDATE public.expense_dispute_resolutions SET status='rejected' WHERE id=r.id;
    ELSIF NOT EXISTS(SELECT 1 FROM unnest(d.required_parties) AS p(id) WHERE NOT EXISTS(SELECT 1 FROM public.expense_resolution_votes WHERE resolution_id=r.id AND actor_id=p.id AND accepted)) THEN
     UPDATE public.expense_dispute_resolutions SET status='agreed' WHERE id=r.id;
     UPDATE public.expense_disputes SET status='resolved',resolution_id=r.id,resolved_at=now() WHERE id=d.id;
    END IF;
   END IF;result:=r.id;
  END IF;
 END IF;
 RETURN public.record_m2_v1(p_operation_id,'m2_review',p_command,result);
END $$;
CREATE FUNCTION public.expense_review_state_v1(p_transaction_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor uuid:=auth.uid();expense public.transactions;ack jsonb;disputes jsonb;changes jsonb;context jsonb;
BEGIN
 PERFORM public.tabby_pre_request();SELECT * INTO expense FROM public.transactions WHERE id=p_transaction_id;
 IF actor IS NULL OR expense.id IS NULL OR NOT public.is_tab_member(expense.tab_id,actor) OR NOT EXISTS(SELECT 1 FROM public.transaction_participants WHERE transaction_id=expense.id AND user_id=actor) THEN RAISE EXCEPTION 'Expense party required' USING ERRCODE='42501';END IF;
 context:=public.expense_change_context_internal(expense.id,actor);
 SELECT coalesce(jsonb_agg(jsonb_build_object('actor_id',s.user_id,'required',s.user_id<>expense.created_by,'acknowledged',a.id IS NOT NULL,'acknowledged_at',a.created_at) ORDER BY s.user_id),'[]') INTO ack FROM public.transaction_participants s LEFT JOIN public.expense_acknowledgments a ON a.transaction_id=s.transaction_id AND a.actor_id=s.user_id WHERE s.transaction_id=expense.id AND s.user_id IS NOT NULL;
 SELECT coalesce(jsonb_agg(value ORDER BY created_at DESC,id),'[]') INTO changes FROM(
 SELECT r.created_at,r.id,jsonb_build_object('id',r.id,'requested_by',r.requested_by,'kind',r.kind,'new_total_centavos',r.new_total_centavos,'reason',r.reason,
 'can_review',o.change_id IS NULL AND NOT EXISTS(SELECT 1 FROM public.expense_change_results WHERE transaction_id=r.transaction_id) AND NOT EXISTS(SELECT 1 FROM public.expense_change_decisions WHERE change_id=r.id AND NOT accepted) AND EXISTS(SELECT 1 FROM public.expense_change_reviewers WHERE change_id=r.id AND reviewer_id=actor) AND NOT EXISTS(SELECT 1 FROM public.expense_change_decisions WHERE change_id=r.id AND actor_id=actor),
 'status',CASE WHEN o.change_id IS NOT NULL THEN 'applied' WHEN EXISTS(SELECT 1 FROM public.expense_change_decisions WHERE change_id=r.id AND NOT accepted) THEN 'rejected' WHEN EXISTS(SELECT 1 FROM public.expense_change_results WHERE transaction_id=r.transaction_id) THEN 'superseded' ELSE 'pending' END,
 'required_reviewers',(SELECT count(*) FROM public.expense_change_reviewers WHERE change_id=r.id),'accepted_reviewers',(SELECT count(*) FROM public.expense_change_reviewers v JOIN public.expense_change_decisions d ON d.change_id=v.change_id AND d.actor_id=v.reviewer_id WHERE v.change_id=r.id AND d.accepted)) value
 FROM public.expense_change_requests r LEFT JOIN public.expense_change_results o ON o.change_id=r.id WHERE r.transaction_id=expense.id ORDER BY r.created_at DESC,r.id LIMIT 50) rows;
 SELECT coalesce(jsonb_agg(value ORDER BY status,created_at DESC,id),'[]') INTO disputes FROM(
 SELECT d.id,d.status,d.created_at,to_jsonb(d)||jsonb_build_object('resolutions',coalesce((SELECT jsonb_agg(to_jsonb(r)||jsonb_build_object('accepted_count',(SELECT count(*) FROM public.expense_resolution_votes WHERE resolution_id=r.id AND accepted),'my_vote',(SELECT accepted FROM public.expense_resolution_votes WHERE resolution_id=r.id AND actor_id=actor)) ORDER BY r.created_at DESC,r.id) FROM (SELECT * FROM public.expense_dispute_resolutions WHERE dispute_id=d.id ORDER BY (status='pending') DESC,created_at DESC,id LIMIT 50) r),'[]')) value
 FROM public.expense_disputes d WHERE transaction_id=expense.id ORDER BY (status='open') DESC,created_at DESC,id LIMIT 50) rows;
 RETURN jsonb_build_object('account_id',actor,'transaction_id',expense.id,'expense',jsonb_build_object('description',expense.description,'total_centavos',expense.total_amount_centavos,'created_by',expense.created_by),'acknowledgments',ack,'proposals',changes,'disputes',disputes,
 'can_acknowledge',context IS NOT NULL AND NOT coalesce((context->>'manual_contact')::boolean,true) AND actor<>expense.created_by AND NOT EXISTS(SELECT 1 FROM public.expense_acknowledgments WHERE transaction_id=expense.id AND actor_id=actor),
 'can_propose',context IS NOT NULL AND coalesce((context->>'can_request')::boolean,false) AND NOT coalesce((context->>'manual_contact')::boolean,true),
 'can_dispute',context IS NOT NULL AND NOT coalesce((context->>'manual_contact')::boolean,true) AND NOT EXISTS(SELECT 1 FROM public.expense_disputes WHERE transaction_id=expense.id AND status='open'));
END $$;
REVOKE ALL ON FUNCTION public.review_expense_v1(uuid,jsonb),public.expense_review_state_v1(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.review_expense_v1(uuid,jsonb),public.expense_review_state_v1(uuid) TO authenticated;
CREATE FUNCTION public.expense_review_history_v1(p_transaction_id uuid,p_section text,p_parent_id uuid DEFAULT NULL,p_after uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor uuid:=auth.uid();records jsonb;last_id uuid;more boolean;expense public.transactions;
BEGIN
 PERFORM public.tabby_pre_request();SELECT * INTO expense FROM public.transactions WHERE id=p_transaction_id;
 IF actor IS NULL OR expense.id IS NULL OR NOT public.is_tab_member(expense.tab_id,actor) OR NOT EXISTS(SELECT 1 FROM public.transaction_participants WHERE transaction_id=expense.id AND user_id=actor) THEN RAISE EXCEPTION 'Expense party required' USING ERRCODE='42501';END IF;
 IF p_section IS NULL OR p_section NOT IN ('proposals','disputes','resolutions') OR (p_section='resolutions' AND NOT EXISTS(SELECT 1 FROM public.expense_disputes WHERE id=p_parent_id AND transaction_id=expense.id)) OR (p_section<>'resolutions' AND p_parent_id IS NOT NULL) THEN RAISE EXCEPTION 'History scope mismatch' USING ERRCODE='22023';END IF;
 WITH candidates AS (
 SELECT r.id,to_jsonb(r)||jsonb_build_object(
 'status',CASE WHEN o.change_id IS NOT NULL THEN 'applied' WHEN EXISTS(SELECT 1 FROM public.expense_change_decisions WHERE change_id=r.id AND NOT accepted) THEN 'rejected' WHEN EXISTS(SELECT 1 FROM public.expense_change_results WHERE transaction_id=r.transaction_id) THEN 'superseded' ELSE 'pending' END,
 'can_review',o.change_id IS NULL AND NOT EXISTS(SELECT 1 FROM public.expense_change_results WHERE transaction_id=r.transaction_id) AND NOT EXISTS(SELECT 1 FROM public.expense_change_decisions WHERE change_id=r.id AND NOT accepted) AND EXISTS(SELECT 1 FROM public.expense_change_reviewers WHERE change_id=r.id AND reviewer_id=actor) AND NOT EXISTS(SELECT 1 FROM public.expense_change_decisions WHERE change_id=r.id AND actor_id=actor)) value
 FROM public.expense_change_requests r LEFT JOIN public.expense_change_results o ON o.change_id=r.id WHERE p_section='proposals' AND r.transaction_id=expense.id
 UNION ALL SELECT d.id,to_jsonb(d)||jsonb_build_object('has_pending_resolution',EXISTS(SELECT 1 FROM public.expense_dispute_resolutions WHERE dispute_id=d.id AND status='pending')) FROM public.expense_disputes d WHERE p_section='disputes' AND transaction_id=expense.id
 UNION ALL SELECT r.id,to_jsonb(r)||jsonb_build_object('required_party_count',cardinality(d.required_parties),'accepted_count',(SELECT count(*) FROM public.expense_resolution_votes WHERE resolution_id=r.id AND accepted),'can_vote',d.status='open' AND r.status='pending' AND actor=ANY(d.required_parties) AND NOT EXISTS(SELECT 1 FROM public.expense_resolution_votes WHERE resolution_id=r.id AND actor_id=actor))
 FROM public.expense_dispute_resolutions r JOIN public.expense_disputes d ON d.id=r.dispute_id WHERE p_section='resolutions' AND d.id=p_parent_id AND d.transaction_id=expense.id
 ),window_rows AS(SELECT * FROM candidates WHERE p_after IS NULL OR id>p_after ORDER BY id LIMIT 51),page AS(SELECT * FROM window_rows ORDER BY id LIMIT 50)
 SELECT coalesce(jsonb_agg(value ORDER BY id),'[]'),(SELECT id FROM page ORDER BY id DESC LIMIT 1),(SELECT count(*)>50 FROM window_rows) INTO records,last_id,more FROM page;
 RETURN jsonb_build_object('account_id',actor,'transaction_id',expense.id,'section',p_section,'parent_id',p_parent_id,'records',records,'next_cursor',CASE WHEN more THEN last_id ELSE NULL END,
 'expense',jsonb_build_object('description',expense.description,'total_centavos',expense.total_amount_centavos));
END $$;
REVOKE ALL ON FUNCTION public.expense_review_history_v1(uuid,text,uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.expense_review_history_v1(uuid,text,uuid,uuid) TO authenticated;

COMMIT;

-- M1 cancellation and reminder guards (additive migration)
BEGIN;

-- CAP-006 / ADR-006: cancellation is a status transition, never deletion or
-- amount mutation. The existing change result and reasoned activity remain the
-- durable revision record; the legacy status audit records the status change.
CREATE OR REPLACE FUNCTION public.prevent_transaction_tampering()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $function$
DECLARE v_uid text:=auth.uid()::text;
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
     OR (NEW.status IS DISTINCT FROM OLD.status AND NOT (
       NEW.status='cancelled' AND EXISTS(
         SELECT 1 FROM public.expense_change_results z
         JOIN public.expense_change_requests r ON r.id=z.change_id
         WHERE z.transaction_id=OLD.id AND r.kind='cancel'
       ))) THEN
    RAISE EXCEPTION 'Financial transaction fields cannot be changed';
  END IF;
  IF NEW.receipt_url IS DISTINCT FROM OLD.receipt_url AND NEW.receipt_url IS NOT NULL AND NEW.receipt_url<>'' THEN
    IF NEW.receipt_url ~* '^[a-z]+://' AND NEW.receipt_url !~* '^(file|content)://' THEN
      RAISE EXCEPTION 'Receipt attachments must be uploaded files';
    END IF;
    IF v_uid IS NOT NULL AND NEW.receipt_url NOT LIKE v_uid||'/%' AND left(NEW.receipt_url,1)<>'/'
       AND NEW.receipt_url !~* '^(file|content)://' AND NEW.receipt_url !~ '^[A-Za-z]:[\\/]' THEN
      RAISE EXCEPTION 'Receipt attachments must belong to the uploader';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.prevent_transaction_tampering() FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.apply_expense_change_internal(p_change_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE change public.expense_change_requests; expense public.transactions;
  payer public.transaction_participants; party public.transaction_participants;
  reversed uuid; first_reversal uuid; replacement uuid; reversals uuid[]:='{}';
  shares jsonb:='[]'; payer_share bigint; new_share bigint;
BEGIN
  SELECT * INTO STRICT change FROM public.expense_change_requests WHERE id=p_change_id;
  PERFORM pg_advisory_xact_lock(hashtextextended(change.transaction_id::text,1));
  IF EXISTS(SELECT 1 FROM public.expense_change_results WHERE transaction_id=change.transaction_id) THEN
    RAISE EXCEPTION 'Expense already revised' USING ERRCODE='22023'; END IF;
  IF EXISTS(SELECT 1 FROM public.expense_change_reviewers r WHERE r.change_id=p_change_id AND NOT EXISTS(
    SELECT 1 FROM public.expense_change_decisions d WHERE d.change_id=r.change_id AND d.actor_id=r.reviewer_id AND d.accepted))
    OR EXISTS(SELECT 1 FROM public.expense_change_decisions WHERE change_id=p_change_id AND NOT accepted) THEN
    RAISE EXCEPTION 'All registered participants must agree' USING ERRCODE='42501'; END IF;
  SELECT * INTO expense FROM public.transactions WHERE id=change.transaction_id FOR SHARE;
  PERFORM 1 FROM public.transaction_participants WHERE transaction_id=expense.id FOR SHARE;
  IF change.original_snapshot IS DISTINCT FROM jsonb_build_object('expense',to_jsonb(expense),'shares',
    (SELECT jsonb_agg(to_jsonb(s) ORDER BY s.id) FROM public.transaction_participants s WHERE transaction_id=expense.id)) THEN
    RAISE EXCEPTION 'Original expense changed; request a fresh review' USING ERRCODE='22023'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(expense.tab_id::text,0));
  SELECT * INTO STRICT payer FROM public.transaction_participants WHERE transaction_id=expense.id AND participant_role='payer';
  payer_share:=change.new_total_centavos;
  FOR party IN SELECT * FROM public.transaction_participants WHERE transaction_id=expense.id AND id<>payer.id ORDER BY id LOOP
    IF change.kind='correct' AND party.share_amount_centavos>0 THEN
      reversed:=public.create_expense_atomic(expense.tab_id,'Reversal: '||expense.description,expense.category,
        party.share_amount_centavos,COALESCE(party.user_id,party.contact_id),jsonb_build_array(
          jsonb_build_object('user_id',party.user_id,'contact_id',party.contact_id,'participant_role','payer','share_amount_centavos',0),
          jsonb_build_object('user_id',payer.user_id,'contact_id',payer.contact_id,'participant_role','debtor','share_amount_centavos',party.share_amount_centavos)),NULL,NULL);
      reversals:=array_append(reversals,reversed);
      IF first_reversal IS NULL THEN first_reversal:=reversed; END IF;
    END IF;
    IF change.kind='correct' THEN
      new_share:=trunc(change.new_total_centavos::numeric*party.share_amount_centavos/expense.total_amount_centavos)::bigint;
      payer_share:=payer_share-new_share;
      shares:=shares||jsonb_build_array(jsonb_build_object('user_id',party.user_id,'contact_id',party.contact_id,
        'participant_role',party.participant_role,'share_amount_centavos',new_share));
    END IF;
  END LOOP;
  IF change.kind='correct' THEN
    shares:=shares||jsonb_build_array(jsonb_build_object('user_id',payer.user_id,'contact_id',payer.contact_id,'participant_role','payer','share_amount_centavos',payer_share));
    replacement:=public.create_expense_atomic(expense.tab_id,expense.description,expense.category,change.new_total_centavos,
      COALESCE(payer.user_id,payer.contact_id),shares,expense.due_date,expense.receipt_url);
  END IF;
  INSERT INTO public.expense_change_results(change_id,transaction_id,reversal_id,replacement_id)
    VALUES(change.id,expense.id,first_reversal,replacement);
  INSERT INTO public.expense_change_outputs(transaction_id,change_id,role)
    SELECT value,change.id,'reversal' FROM unnest(reversals) value ON CONFLICT DO NOTHING;
  IF change.kind='cancel' THEN
    -- Retain the original transaction and shares; update only lifecycle status.
    UPDATE public.transactions SET status='cancelled' WHERE id=expense.id AND status<>'cancelled';
  END IF;
  INSERT INTO public.activity_logs(actor_user_id,tab_id,transaction_id,event_type,metadata)
    VALUES(auth.uid(),expense.tab_id,expense.id,'EXPENSE_CHANGE_APPLIED',jsonb_build_object('change_id',change.id,
      'kind',change.kind,'reason',change.reason,'manual_contact_agreement',change.manual_contact_agreement,
      'reversal_ids',to_jsonb(reversals),'replacement_id',replacement));
  INSERT INTO public.notifications(recipient_user_id,notification_type,related_tab_id,related_transaction_id,title,body)
    SELECT DISTINCT s.user_id,'amount_changed',expense.tab_id,expense.id,'Expense change accepted',
      'Your shared history now includes the agreed revision.' FROM public.transaction_participants s
      WHERE s.transaction_id=expense.id AND s.user_id IS NOT NULL AND s.user_id<>auth.uid();
END $$;
REVOKE ALL ON FUNCTION public.apply_expense_change_internal(uuid) FROM PUBLIC,anon,authenticated;

-- HOME-002: preserve reminder rows as cancelled history after a pair settles.
-- Pair scoping prevents one group member's settlement from clearing others.
CREATE FUNCTION public.cancel_settled_pair_reminders_v1() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  IF NEW.status='confirmed' AND OLD.status IS DISTINCT FROM NEW.status
    AND COALESCE(NEW.payer_user_id,NEW.submitted_by) IS NOT NULL AND NEW.recipient_user_id IS NOT NULL THEN
    UPDATE public.reminders r SET status='cancelled'
      FROM public.transactions t
      WHERE r.transaction_id=t.id AND t.tab_id=NEW.tab_id AND r.status='scheduled'
        AND r.recipient_user_id=COALESCE(NEW.payer_user_id,NEW.submitted_by)
        AND r.created_by=NEW.recipient_user_id
        AND public.get_pair_outstanding(NEW.tab_id,COALESCE(NEW.payer_user_id,NEW.submitted_by),NEW.recipient_user_id)<=0;
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.cancel_settled_pair_reminders_v1() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER cancel_settled_pair_reminders
  AFTER UPDATE OF status ON public.payments
  FOR EACH ROW EXECUTE FUNCTION public.cancel_settled_pair_reminders_v1();

-- Repair legacy stale scheduled rows without deleting reminder history.
UPDATE public.reminders r SET status='cancelled'
  FROM public.transactions t
  WHERE r.transaction_id=t.id AND r.status='scheduled'
    AND public.get_pair_outstanding(t.tab_id,r.recipient_user_id,r.created_by)<=0;

-- HOME-004: idempotent replay is resolved before throttling. A new operation
-- inside the six-hour sender/tab/recipient window receives the stable PostgREST
-- contract HTTP 429 / SQLSTATE PT429 and commits no notification or operation.
CREATE OR REPLACE FUNCTION public.send_tab_reminder_v1(p_operation_id uuid, p_command jsonb)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  actor uuid := auth.uid();
  previous public.reminder_operations%ROWTYPE;
  v_tab_id uuid;
  recipient uuid;
  result uuid;
BEGIN
  IF actor IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='42501'; END IF;
  IF p_operation_id IS NULL OR p_command IS NULL OR jsonb_typeof(p_command)<>'object' THEN
    RAISE EXCEPTION 'Reminder command required' USING ERRCODE='22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':reminder',0));
  SELECT * INTO previous FROM public.reminder_operations
    WHERE actor_id=actor AND operation_id=p_operation_id;
  IF FOUND THEN
    IF previous.command<>p_command THEN RAISE EXCEPTION 'Operation payload conflict' USING ERRCODE='22023'; END IF;
    RETURN previous.notification_id;
  END IF;
  v_tab_id := (p_command->>'tab_id')::uuid;
  recipient := (p_command->>'recipient_user_id')::uuid;
  IF recipient IS NULL OR recipient=actor OR NOT EXISTS (
      SELECT 1 FROM public.tabs t JOIN public.tab_members a ON a.tab_id=t.id
      JOIN public.tab_members b ON b.tab_id=t.id WHERE t.id=v_tab_id
      AND t.status='active' AND a.user_id=actor AND b.user_id=recipient
      AND (t.group_id IS NULL OR (
        EXISTS(SELECT 1 FROM public.group_members g WHERE g.group_id=t.group_id AND g.user_id=actor AND g.status='active')
        AND EXISTS(SELECT 1 FROM public.group_members g WHERE g.group_id=t.group_id AND g.user_id=recipient AND g.status='active')))) THEN
    RAISE EXCEPTION 'Active shared tab required' USING ERRCODE='42501';
  END IF;
  -- Share the financial pair lock with payment confirmation so a reminder
  -- cannot pass its debt check concurrently with settlement.
  PERFORM pg_advisory_xact_lock(hashtextextended(v_tab_id::text,0));
  IF public.get_pair_outstanding(v_tab_id,recipient,actor)<=0 THEN
    RAISE EXCEPTION 'Recipient has no outstanding obligation to sender' USING ERRCODE='22023';
  END IF;
  IF coalesce(length(btrim(p_command->>'title')),0) NOT BETWEEN 1 AND 120 OR
     coalesce(length(btrim(p_command->>'body')),0) NOT BETWEEN 1 AND 1000 THEN
    RAISE EXCEPTION 'Reminder title/body invalid' USING ERRCODE='22023';
  END IF;
  IF EXISTS (SELECT 1 FROM public.reminder_operations r WHERE r.actor_id=actor
      AND r.command->>'tab_id'=v_tab_id::text AND r.command->>'recipient_user_id'=recipient::text
      AND r.accepted_at>now()-interval '6 hours') THEN
    RAISE SQLSTATE 'PT429'
      USING MESSAGE='Reminder rate limit exceeded',
        DETAIL='A reminder was already accepted for this tab and recipient within the last six hours',
        HINT='Retry after the six-hour pair window expires';
  END IF;
  INSERT INTO public.notifications(recipient_user_id,notification_type,related_tab_id,title,body)
    VALUES(recipient,'manual_nudge',v_tab_id,btrim(p_command->>'title'),btrim(p_command->>'body'))
    RETURNING id INTO result;
  INSERT INTO public.activity_logs(id,actor_user_id,tab_id,event_type,metadata)
    VALUES(result,actor,v_tab_id,'REMINDER_SENT',jsonb_build_object('recipient_id',recipient,'notification_id',result));
  INSERT INTO public.reminder_operations(actor_id,operation_id,command,notification_id)
    VALUES(actor,p_operation_id,p_command,result);
  RETURN result;
END; $$;
REVOKE ALL ON FUNCTION public.send_tab_reminder_v1(uuid,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.send_tab_reminder_v1(uuid,jsonb) TO authenticated;

COMMIT;

-- M1 normalized malformed financial input responses
-- Normalize malformed JSON-backed financial input at the PostgREST boundary.
-- PT400 is the existing project convention for a stable HTTP 400 response.
CREATE FUNCTION public.raise_financial_input_validation_v1() RETURNS void
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
BEGIN
  RAISE SQLSTATE 'PT400' USING MESSAGE='Invalid financial input. Enter amounts as whole centavos and check the submitted values.';
END $$;
REVOKE ALL ON FUNCTION public.raise_financial_input_validation_v1() FROM PUBLIC,anon,authenticated;

-- Keep the public RPC signatures stable while catching PostgreSQL text-to-number
-- and range errors raised by nested validators. Raw SQLSTATE/details never cross
-- the client boundary. The unchecked implementations remain private helpers.
ALTER FUNCTION public.create_expense_v1(uuid,jsonb) RENAME TO create_expense_v1_unmapped;
REVOKE ALL ON FUNCTION public.create_expense_v1_unmapped(uuid,jsonb) FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.create_expense_v1(p_operation_id uuid,p_command jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  RETURN public.create_expense_v1_unmapped(p_operation_id,p_command);
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
  PERFORM public.raise_financial_input_validation_v1();
END $$;
GRANT EXECUTE ON FUNCTION public.create_expense_v1(uuid,jsonb) TO authenticated;

ALTER FUNCTION public.submit_payment_v1(uuid,jsonb) RENAME TO submit_payment_v1_unmapped;
REVOKE ALL ON FUNCTION public.submit_payment_v1_unmapped(uuid,jsonb) FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.submit_payment_v1(p_operation_id uuid,p_command jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  RETURN public.submit_payment_v1_unmapped(p_operation_id,p_command);
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
  PERFORM public.raise_financial_input_validation_v1();
END $$;
GRANT EXECUTE ON FUNCTION public.submit_payment_v1(uuid,jsonb) TO authenticated;

ALTER FUNCTION public.record_received_payment_v1(uuid,jsonb) RENAME TO record_received_payment_v1_unmapped;
REVOKE ALL ON FUNCTION public.record_received_payment_v1_unmapped(uuid,jsonb) FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.record_received_payment_v1(p_operation_id uuid,p_command jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  RETURN public.record_received_payment_v1_unmapped(p_operation_id,p_command);
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
  PERFORM public.raise_financial_input_validation_v1();
END $$;
GRANT EXECUTE ON FUNCTION public.record_received_payment_v1(uuid,jsonb) TO authenticated;

ALTER FUNCTION public.submit_payment_v2(uuid,jsonb) RENAME TO submit_payment_v2_unmapped;
REVOKE ALL ON FUNCTION public.submit_payment_v2_unmapped(uuid,jsonb) FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.submit_payment_v2(p_operation_id uuid,p_command jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  RETURN public.submit_payment_v2_unmapped(p_operation_id,p_command);
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
  PERFORM public.raise_financial_input_validation_v1();
END $$;
GRANT EXECUTE ON FUNCTION public.submit_payment_v2(uuid,jsonb) TO authenticated;

-- These M2 RPCs remain disabled by their feature flags. Their error boundary is
-- still normalized so enabling a feature cannot expose raw numeric parser errors.
ALTER FUNCTION public.create_expense_v3(uuid,jsonb) RENAME TO create_expense_v3_unmapped;
REVOKE ALL ON FUNCTION public.create_expense_v3_unmapped(uuid,jsonb) FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.create_expense_v3(p_operation_id uuid,p_command jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  RETURN public.create_expense_v3_unmapped(p_operation_id,p_command);
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
  PERFORM public.raise_financial_input_validation_v1();
END $$;
GRANT EXECUTE ON FUNCTION public.create_expense_v3(uuid,jsonb) TO authenticated;

ALTER FUNCTION public.change_recurrence_v1(uuid,jsonb) RENAME TO change_recurrence_v1_unmapped;
REVOKE ALL ON FUNCTION public.change_recurrence_v1_unmapped(uuid,jsonb) FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.change_recurrence_v1(p_operation_id uuid,p_command jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  RETURN public.change_recurrence_v1_unmapped(p_operation_id,p_command);
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
  PERFORM public.raise_financial_input_validation_v1();
END $$;
GRANT EXECUTE ON FUNCTION public.change_recurrence_v1(uuid,jsonb) TO authenticated;

ALTER FUNCTION public.materialize_recurrence_v1(uuid,jsonb) RENAME TO materialize_recurrence_v1_unmapped;
REVOKE ALL ON FUNCTION public.materialize_recurrence_v1_unmapped(uuid,jsonb) FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.materialize_recurrence_v1(p_operation_id uuid,p_command jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  RETURN public.materialize_recurrence_v1_unmapped(p_operation_id,p_command);
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
  PERFORM public.raise_financial_input_validation_v1();
END $$;
GRANT EXECUTE ON FUNCTION public.materialize_recurrence_v1(uuid,jsonb) TO authenticated;

ALTER FUNCTION public.review_expense_v1(uuid,jsonb) RENAME TO review_expense_v1_unmapped;
REVOKE ALL ON FUNCTION public.review_expense_v1_unmapped(uuid,jsonb) FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.review_expense_v1(p_operation_id uuid,p_command jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  RETURN public.review_expense_v1_unmapped(p_operation_id,p_command);
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
  PERFORM public.raise_financial_input_validation_v1();
END $$;
GRANT EXECUTE ON FUNCTION public.review_expense_v1(uuid,jsonb) TO authenticated;

-- 20261113000001_friendship_rpc_only.sql
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

-- 20261113000002_friend_request_pair_lock.sql
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
