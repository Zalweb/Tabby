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
