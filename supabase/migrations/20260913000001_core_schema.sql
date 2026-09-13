-- Tabby Database Migration: 20260913000001_core_schema.sql
-- Description: Creates the complete 17-entity relational data schema for Tabby.
-- Specifications: AGENTS.md Section 7, Section 8, ADR-001 (Integer Centavos BIGINT), ADR-011 (Supabase BaaS).
-- Currency Standard: Philippine Peso integer centavos (1 PHP = 100 centavos).

-- ============================================================================
-- 0. EXTENSIONS & PREREQUISITES
-- ============================================================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================================
-- 1. USERS TABLE
-- Primary authenticated user accounts.
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT UNIQUE,
    phone TEXT UNIQUE,
    display_name TEXT NOT NULL,
    avatar_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Link to auth.users if running in Supabase environment
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

-- ============================================================================
-- 2. CONTACTS TABLE
-- Virtual contacts created by a user for counterparts not yet on Tabby.
-- ============================================================================
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

-- ============================================================================
-- 3. FRIENDSHIPS TABLE
-- Social relationship between two authenticated users. Decoupled from financial records.
-- ============================================================================
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

-- ============================================================================
-- 4. GROUPS TABLE
-- Social circles or shared contexts (e.g., Roommates, Barkada).
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.groups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_by UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    name TEXT NOT NULL,
    description TEXT,
    avatar_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- 5. GROUP_MEMBERS TABLE
-- Membership roster in a group.
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.group_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id UUID NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    role TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('admin', 'member')),
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'invited', 'left')),
    joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT unique_group_member UNIQUE (group_id, user_id)
);

-- ============================================================================
-- 6. GROUP_PERMISSIONS TABLE
-- Configurable permissions per group.
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.group_permissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id UUID NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
    permission_key TEXT NOT NULL,
    enabled BOOLEAN NOT NULL DEFAULT true,
    CONSTRAINT unique_group_permission UNIQUE (group_id, permission_key)
);

-- ============================================================================
-- 7. TABS TABLE
-- The running bilateral or multi-party ledger.
-- ============================================================================
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
-- Enforces that exactly one active 1-on-1 tab exists between any two users.
CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_bilateral_tab ON public.tabs (
    LEAST(user_a, user_b),
    GREATEST(user_a, user_b)
) WHERE tab_type = 'individual' AND status = 'active' AND user_a IS NOT NULL AND user_b IS NOT NULL;

-- ============================================================================
-- 8. TAB_MEMBERS TABLE
-- Participants in a Tab. Either user_id or contact_id must be non-null.
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.tab_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tab_id UUID NOT NULL REFERENCES public.tabs(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    contact_id UUID REFERENCES public.contacts(id) ON DELETE CASCADE,
    role TEXT NOT NULL DEFAULT 'participant' CHECK (role IN ('participant', 'admin', 'viewer')),
    joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT check_tab_member_party CHECK (user_id IS NOT NULL OR contact_id IS NOT NULL)
);

-- Avoid duplicate membership rows within a tab
CREATE UNIQUE INDEX IF NOT EXISTS idx_tab_members_unique_user ON public.tab_members (tab_id, user_id) WHERE user_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_tab_members_unique_contact ON public.tab_members (tab_id, contact_id) WHERE contact_id IS NOT NULL;

-- ============================================================================
-- 9. RECURRING_RULES TABLE
-- Configuration template that generates scheduled periodic transactions.
-- ============================================================================
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

-- ============================================================================
-- 10. TRANSACTIONS TABLE
-- Financial obligations or shared expense events belonging to a Tab.
-- ============================================================================
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
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- 11. TRANSACTION_PARTICIPANTS TABLE
-- Individual participant allocations and acknowledgment status.
-- ============================================================================
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

-- ============================================================================
-- 12. PAYMENTS TABLE
-- Recorded settlements against a Tab (proof-tracked; non-custodial).
-- ============================================================================
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

-- ============================================================================
-- 13. PAYMENT_PROOFS TABLE
-- Attached receipt screenshots or proof images (e.g., GCash / Maya confirmation).
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.payment_proofs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_id UUID NOT NULL REFERENCES public.payments(id) ON DELETE CASCADE,
    file_url TEXT NOT NULL,
    file_name TEXT NOT NULL,
    mime_type TEXT NOT NULL,
    uploaded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- 14. REMINDERS TABLE
-- Scheduled automated or manual nudge reminders.
-- ============================================================================
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

-- ============================================================================
-- 15. NOTIFICATIONS TABLE
-- High-priority in-app inbox and push notification queue.
-- ============================================================================
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

-- ============================================================================
-- 16. REPORTS TABLE
-- Formal user disputes over amount modifications or unrecognized debts.
-- ============================================================================
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

-- ============================================================================
-- 17. ACTIVITY_LOGS TABLE
-- Immutable append-only audit trail recording every state mutation.
-- ============================================================================
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

-- ============================================================================
-- INDEXES FOR HIGH QUERY PERFORMANCE
-- ============================================================================
-- Contacts
CREATE INDEX IF NOT EXISTS idx_contacts_owner ON public.contacts(owner_user_id);
CREATE INDEX IF NOT EXISTS idx_contacts_claimed ON public.contacts(claimed_user_id);
CREATE INDEX IF NOT EXISTS idx_contacts_phone ON public.contacts(phone);
CREATE INDEX IF NOT EXISTS idx_contacts_email ON public.contacts(email);

-- Friendships
CREATE INDEX IF NOT EXISTS idx_friendships_requester ON public.friendships(requester_id);
CREATE INDEX IF NOT EXISTS idx_friendships_addressee ON public.friendships(addressee_id);
CREATE INDEX IF NOT EXISTS idx_friendships_status ON public.friendships(status);

-- Groups & Members
CREATE INDEX IF NOT EXISTS idx_groups_created_by ON public.groups(created_by);
CREATE INDEX IF NOT EXISTS idx_group_members_group ON public.group_members(group_id);
CREATE INDEX IF NOT EXISTS idx_group_members_user ON public.group_members(user_id);
CREATE INDEX IF NOT EXISTS idx_group_permissions_group ON public.group_permissions(group_id);

-- Tabs & Members
CREATE INDEX IF NOT EXISTS idx_tabs_group ON public.tabs(group_id);
CREATE INDEX IF NOT EXISTS idx_tabs_status ON public.tabs(status);
CREATE INDEX IF NOT EXISTS idx_tabs_user_a ON public.tabs(user_a);
CREATE INDEX IF NOT EXISTS idx_tabs_user_b ON public.tabs(user_b);
CREATE INDEX IF NOT EXISTS idx_tab_members_tab ON public.tab_members(tab_id);
CREATE INDEX IF NOT EXISTS idx_tab_members_user ON public.tab_members(user_id);
CREATE INDEX IF NOT EXISTS idx_tab_members_contact ON public.tab_members(contact_id);

-- Recurring Rules
CREATE INDEX IF NOT EXISTS idx_recurring_rules_tab ON public.recurring_rules(tab_id);
CREATE INDEX IF NOT EXISTS idx_recurring_rules_created_by ON public.recurring_rules(created_by);
CREATE INDEX IF NOT EXISTS idx_recurring_rules_active ON public.recurring_rules(active);

-- Transactions & Participants
CREATE INDEX IF NOT EXISTS idx_transactions_tab ON public.transactions(tab_id);
CREATE INDEX IF NOT EXISTS idx_transactions_created_by ON public.transactions(created_by);
CREATE INDEX IF NOT EXISTS idx_transactions_date ON public.transactions(transaction_date);
CREATE INDEX IF NOT EXISTS idx_transactions_status ON public.transactions(status);
CREATE INDEX IF NOT EXISTS idx_transactions_recurring_rule ON public.transactions(recurring_rule_id);
CREATE INDEX IF NOT EXISTS idx_trans_participants_tx ON public.transaction_participants(transaction_id);
CREATE INDEX IF NOT EXISTS idx_trans_participants_user ON public.transaction_participants(user_id);
CREATE INDEX IF NOT EXISTS idx_trans_participants_contact ON public.transaction_participants(contact_id);

-- Payments & Proofs
CREATE INDEX IF NOT EXISTS idx_payments_tab ON public.payments(tab_id);
CREATE INDEX IF NOT EXISTS idx_payments_submitted_by ON public.payments(submitted_by);
CREATE INDEX IF NOT EXISTS idx_payments_confirmed_by ON public.payments(confirmed_by);
CREATE INDEX IF NOT EXISTS idx_payments_status ON public.payments(status);
CREATE INDEX IF NOT EXISTS idx_payment_proofs_payment ON public.payment_proofs(payment_id);

-- Reminders & Notifications
CREATE INDEX IF NOT EXISTS idx_reminders_tx ON public.reminders(transaction_id);
CREATE INDEX IF NOT EXISTS idx_reminders_recipient ON public.reminders(recipient_user_id);
CREATE INDEX IF NOT EXISTS idx_reminders_status ON public.reminders(status);
CREATE INDEX IF NOT EXISTS idx_reminders_scheduled ON public.reminders(scheduled_for);
CREATE INDEX IF NOT EXISTS idx_notifications_recipient ON public.notifications(recipient_user_id, is_read);
CREATE INDEX IF NOT EXISTS idx_notifications_created ON public.notifications(created_at DESC);

-- Reports & Activity Logs
CREATE INDEX IF NOT EXISTS idx_reports_reported_by ON public.reports(reported_by);
CREATE INDEX IF NOT EXISTS idx_reports_tab ON public.reports(tab_id);
CREATE INDEX IF NOT EXISTS idx_reports_status ON public.reports(status);
CREATE INDEX IF NOT EXISTS idx_activity_logs_tab ON public.activity_logs(tab_id);
CREATE INDEX IF NOT EXISTS idx_activity_logs_actor ON public.activity_logs(actor_user_id);
CREATE INDEX IF NOT EXISTS idx_activity_logs_tx ON public.activity_logs(transaction_id);
CREATE INDEX IF NOT EXISTS idx_activity_logs_payment ON public.activity_logs(payment_id);
CREATE INDEX IF NOT EXISTS idx_activity_logs_created ON public.activity_logs(created_at DESC);

-- ============================================================================
-- AUTH PROFILE SYNCHRONIZATION TRIGGER (Supabase Auth Integration)
-- Automatically provisions public.users profile when auth.users signs up.
-- ============================================================================
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
