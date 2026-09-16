-- Tabby Database Migration: 20260913000004_storage_and_triggers.sql
-- Description: Configures private storage bucket 'payment-proofs', automated updated_at triggers, and activity audit log triggers.
-- Specifications: AGENTS.md Section 7.4, 7.5, ADR-006 (Non-Destructive Cancellation), ADR-011 (Supabase Storage).

-- ============================================================================
-- 1. STORAGE BUCKET CONFIGURATION ('payment-proofs')
-- Private, access-controlled bucket for GCash and Maya transaction screenshots.
-- ============================================================================
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

-- Storage RLS Policies
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'storage' AND table_name = 'objects'
    ) THEN
        -- Allow authenticated users to upload payment proofs into their isolated user folder
        DROP POLICY IF EXISTS "Authenticated users can upload payment proofs" ON storage.objects;
        CREATE POLICY "Authenticated users can upload payment proofs"
            ON storage.objects FOR INSERT
            TO authenticated
            WITH CHECK (
                bucket_id = 'payment-proofs' 
                AND (
                    (storage.foldername(name))[1] = auth.uid()::text
                    OR name LIKE auth.uid()::text || '/%'
                    OR (storage.foldername(name))[1] = 'receipts'
                )
            );

        -- Allow users to read payment proofs they uploaded, or attached to tabs they are members of
        DROP POLICY IF EXISTS "Authenticated users can view payment proofs" ON storage.objects;
        CREATE POLICY "Authenticated users can view payment proofs"
            ON storage.objects FOR SELECT
            TO authenticated
            USING (
                bucket_id = 'payment-proofs'
                AND (
                    -- Owner / uploader
                    (storage.foldername(name))[1] = auth.uid()::text
                    OR name LIKE auth.uid()::text || '/%'
                    -- Counterpart / participant in the associated tab payment
                    OR EXISTS (
                        SELECT 1 FROM public.payment_proofs pp
                        JOIN public.payments p ON pp.payment_id = p.id
                        WHERE (pp.file_url = name OR pp.file_name = name OR pp.file_url LIKE '%' || name)
                          AND public.is_tab_member(p.tab_id, auth.uid())
                    )
                    -- Counterpart / participant in the associated tab transaction
                    OR EXISTS (
                        SELECT 1 FROM public.transactions tx
                        WHERE (tx.receipt_url = name OR tx.receipt_url LIKE '%' || name)
                          AND public.is_tab_member(tx.tab_id, auth.uid())
                    )
                )
            );

        -- Allow users to delete only their own uploads
        DROP POLICY IF EXISTS "Users can delete their own payment proofs" ON storage.objects;
        CREATE POLICY "Users can delete their own payment proofs"
            ON storage.objects FOR DELETE
            TO authenticated
            USING (
                bucket_id = 'payment-proofs' 
                AND (
                    (storage.foldername(name))[1] = auth.uid()::text
                    OR name LIKE auth.uid()::text || '/%'
                )
            );

        -- Allow users to update only their own uploads
        DROP POLICY IF EXISTS "Users can update their own payment proofs" ON storage.objects;
        CREATE POLICY "Users can update their own payment proofs"
            ON storage.objects FOR UPDATE
            TO authenticated
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

-- ============================================================================
-- 2. AUTOMATED updated_at TIMESTAMP TRIGGERS
-- ============================================================================
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger: users
DROP TRIGGER IF EXISTS trigger_users_updated_at ON public.users;
CREATE TRIGGER trigger_users_updated_at
    BEFORE UPDATE ON public.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- Trigger: groups
DROP TRIGGER IF EXISTS trigger_groups_updated_at ON public.groups;
CREATE TRIGGER trigger_groups_updated_at
    BEFORE UPDATE ON public.groups
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- Trigger: tabs
DROP TRIGGER IF EXISTS trigger_tabs_updated_at ON public.tabs;
CREATE TRIGGER trigger_tabs_updated_at
    BEFORE UPDATE ON public.tabs
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- Trigger: transactions
DROP TRIGGER IF EXISTS trigger_transactions_updated_at ON public.transactions;
CREATE TRIGGER trigger_transactions_updated_at
    BEFORE UPDATE ON public.transactions
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- Trigger: recurring_rules
DROP TRIGGER IF EXISTS trigger_recurring_rules_updated_at ON public.recurring_rules;
CREATE TRIGGER trigger_recurring_rules_updated_at
    BEFORE UPDATE ON public.recurring_rules
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- ============================================================================
-- 3. ACTIVITY LOGGING TRIGGERS (Append-Only Audit Trail)
-- Captures state mutations into public.activity_logs per Section 7.4.
-- ============================================================================

-- Trigger function for Transactions
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

-- Trigger function for Payments
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

-- Trigger function for Reports
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

-- ============================================================================
-- 4. VALIDATION HELPER: TRANSACTION SPLIT SUM
-- Validates that participant shares sum to the total transaction amount.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.validate_transaction_split(p_transaction_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    v_total BIGINT;
    v_sum_shares BIGINT;
BEGIN
    SELECT total_amount_centavos INTO v_total
    FROM public.transactions
    WHERE id = p_transaction_id;

    IF v_total IS NULL THEN
        RETURN FALSE;
    END IF;

    SELECT COALESCE(SUM(share_amount_centavos), 0) INTO v_sum_shares
    FROM public.transaction_participants
    WHERE transaction_id = p_transaction_id
      AND participant_role IN ('debtor', 'beneficiary');

    RETURN v_total = v_sum_shares;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;
