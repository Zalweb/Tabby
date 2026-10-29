-- Money integrity hardening.
-- Keeps every transaction's payer unique and makes split validation account
-- for the payer's own share instead of requiring debtors to equal the full bill.

CREATE UNIQUE INDEX IF NOT EXISTS idx_transaction_one_payer
  ON public.transaction_participants (transaction_id)
  WHERE participant_role = 'payer';

CREATE OR REPLACE FUNCTION public.validate_transaction_split(p_transaction_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    v_total BIGINT;
    v_all_shares BIGINT;
    v_payer_share BIGINT;
    v_debtor_shares BIGINT;
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
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = public, pg_temp;

ALTER FUNCTION public.validate_transaction_split(UUID)
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
BEGIN
    PERFORM pg_advisory_xact_lock(
        hashtextextended(NEW.tab_id::TEXT, 0)
    );

    IF NOT public.is_tab_member(NEW.tab_id, NEW.submitted_by) THEN
        RAISE EXCEPTION 'Payment submitter is not a member of this tab';
    END IF;

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
