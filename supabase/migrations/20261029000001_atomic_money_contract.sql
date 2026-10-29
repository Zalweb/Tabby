-- Tabby Database Migration: 20261029000001_atomic_money_contract.sql
-- Description: Atomic expense and payment RPCs for mobile clients.
-- Currency standard: integer Philippine Peso centavos (BIGINT).

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

-- Existing rows were historically interpreted as being paid to the confirmer.
UPDATE public.payments
SET recipient_user_id = confirmed_by
WHERE recipient_user_id IS NULL
  AND confirmed_by IS NOT NULL;

CREATE OR REPLACE FUNCTION public.get_pair_outstanding(
    p_tab_id UUID,
    p_debtor_user_id UUID,
    p_payee_user_id UUID
)
RETURNS BIGINT AS $$
DECLARE
    v_owed_to_payee BIGINT := 0;
    v_owed_to_debtor BIGINT := 0;
    v_paid_to_payee BIGINT := 0;
    v_paid_to_debtor BIGINT := 0;
BEGIN
    IF p_tab_id IS NULL
       OR p_debtor_user_id IS NULL
       OR p_payee_user_id IS NULL
       OR p_debtor_user_id = p_payee_user_id THEN
        RETURN 0;
    END IF;

    SELECT COALESCE(SUM(tp.share_amount_centavos), 0)
    INTO v_owed_to_payee
    FROM public.transactions t
    JOIN public.transaction_participants tp ON tp.transaction_id = t.id
    WHERE t.tab_id = p_tab_id
      AND t.status NOT IN ('cancelled', 'disputed')
      AND public.get_transaction_payer_id(t.id) = p_payee_user_id
      AND tp.participant_role IN ('debtor', 'beneficiary')
      AND tp.user_id = p_debtor_user_id;

    SELECT COALESCE(SUM(tp.share_amount_centavos), 0)
    INTO v_owed_to_debtor
    FROM public.transactions t
    JOIN public.transaction_participants tp ON tp.transaction_id = t.id
    WHERE t.tab_id = p_tab_id
      AND t.status NOT IN ('cancelled', 'disputed')
      AND public.get_transaction_payer_id(t.id) = p_debtor_user_id
      AND tp.participant_role IN ('debtor', 'beneficiary')
      AND tp.user_id = p_payee_user_id;

    SELECT COALESCE(SUM(p.amount_centavos), 0)
    INTO v_paid_to_payee
    FROM public.payments p
    WHERE p.tab_id = p_tab_id
      AND p.status = 'confirmed'
      AND p.submitted_by = p_debtor_user_id
      AND p.recipient_user_id = p_payee_user_id;

    SELECT COALESCE(SUM(p.amount_centavos), 0)
    INTO v_paid_to_debtor
    FROM public.payments p
    WHERE p.tab_id = p_tab_id
      AND p.status = 'confirmed'
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
        IF v_share < 0 THEN
            RAISE EXCEPTION 'Participant share cannot be negative';
        END IF;
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
        IF v_contact_id IS NOT NULL
           AND NOT EXISTS (
               SELECT 1 FROM public.tab_members tm
               WHERE tm.tab_id = p_tab_id AND tm.contact_id = v_contact_id
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

CREATE OR REPLACE FUNCTION public.submit_payment(
    p_tab_id UUID,
    p_submitted_by_user_id UUID,
    p_recipient_user_id UUID,
    p_amount_centavos BIGINT,
    p_payment_method TEXT,
    p_note TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_submitter UUID := auth.uid();
    v_payment_id UUID;
    v_status TEXT := 'submitted';
    v_confirmed_by UUID := NULL;
    v_outstanding BIGINT;
BEGIN
    IF v_submitter IS NULL
       OR p_submitted_by_user_id IS NULL
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

    -- A payee may record a payment on behalf of a debtor; normal debtor
    -- submissions remain pending until the payee confirms them.
    IF v_submitter = p_recipient_user_id THEN
        v_status := 'confirmed';
        v_confirmed_by := v_submitter;
    END IF;

    INSERT INTO public.payments (
        tab_id, submitted_by, recipient_user_id, amount_centavos,
        payment_method, note, status, confirmed_by, confirmed_at
    ) VALUES (
        p_tab_id, p_submitted_by_user_id, p_recipient_user_id, p_amount_centavos,
        p_payment_method, p_note, v_status, v_confirmed_by,
        CASE WHEN v_confirmed_by IS NULL THEN NULL ELSE now() END
    )
    RETURNING id INTO v_payment_id;

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
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    SELECT * INTO v_payment
    FROM public.payments
    WHERE id = p_payment_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Payment not found';
    END IF;
    IF v_payment.status <> 'submitted' THEN
        RAISE EXCEPTION 'Only submitted payments can be confirmed';
    END IF;
    IF v_payment.recipient_user_id IS DISTINCT FROM auth.uid() THEN
        RAISE EXCEPTION 'Only the payment recipient can confirm this payment';
    END IF;

    v_outstanding := public.get_pair_outstanding(
        v_payment.tab_id,
        v_payment.submitted_by,
        v_payment.recipient_user_id
    );
    IF v_payment.amount_centavos > v_outstanding THEN
        RAISE EXCEPTION 'Payment exceeds the outstanding balance';
    END IF;

    UPDATE public.payments
    SET status = 'confirmed',
        confirmed_by = auth.uid(),
        confirmed_at = now()
    WHERE id = p_payment_id
      AND status = 'submitted';

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
