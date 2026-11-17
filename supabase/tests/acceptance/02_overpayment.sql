-- Acceptance: a payment larger than the pair's outstanding balance is rejected.
-- Rolls back on success and reports ACCEPTANCE_OK.
DO $$
DECLARE
    a UUID;
    b UUID;
    v_tab UUID := gen_random_uuid();
BEGIN
    SELECT id INTO a FROM public.users ORDER BY created_at, id LIMIT 1;
    SELECT id INTO b FROM public.users WHERE id <> a ORDER BY created_at, id LIMIT 1;
    IF a IS NULL OR b IS NULL THEN
        RAISE EXCEPTION 'ACCEPTANCE_SKIPPED needs at least two users';
    END IF;

    INSERT INTO public.tabs (id, tab_type, status) VALUES (v_tab, 'individual', 'active');
    INSERT INTO public.tab_members (tab_id, user_id, role) VALUES
        (v_tab, a, 'admin'), (v_tab, b, 'participant');

    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', a, 'role', 'authenticated')::text, true);
    PERFORM public.create_expense_atomic(
        v_tab, 'Overpayment check', 'food', 10000, a,
        jsonb_build_array(
            jsonb_build_object('user_id', a, 'participant_role', 'payer',
                               'share_amount_centavos', 5000),
            jsonb_build_object('user_id', b, 'participant_role', 'debtor',
                               'share_amount_centavos', 5000)
        ), NULL, NULL);

    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', b, 'role', 'authenticated')::text, true);

    BEGIN
        PERFORM public.submit_payment(v_tab, b, a, 6000, 'cash', NULL);
        RAISE EXCEPTION 'ASSERT overpayment accepted';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM LIKE '%exceeds%' THEN
                RAISE EXCEPTION 'ACCEPTANCE_OK overpayment rejected: %', SQLERRM;
            END IF;
            RAISE EXCEPTION 'ACCEPTANCE_FAIL unexpected error: %', SQLERRM;
    END;

    RAISE EXCEPTION 'ASSERT unreachable';
END;
$$;
