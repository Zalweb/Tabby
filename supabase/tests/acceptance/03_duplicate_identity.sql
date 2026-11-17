-- Acceptance: the same participant identity cannot appear twice on one transaction.
-- Rolls back on success and reports ACCEPTANCE_OK.
DO $$
DECLARE
    a UUID;
    b UUID;
    v_tab UUID := gen_random_uuid();
    v_tx UUID;
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
    v_tx := public.create_expense_atomic(
        v_tab, 'Duplicate identity check', 'food', 10000, a,
        jsonb_build_array(
            jsonb_build_object('user_id', a, 'participant_role', 'payer',
                               'share_amount_centavos', 5000),
            jsonb_build_object('user_id', b, 'participant_role', 'debtor',
                               'share_amount_centavos', 5000)
        ), NULL, NULL);

    BEGIN
        INSERT INTO public.transaction_participants
            (transaction_id, user_id, participant_role, share_amount_centavos)
        VALUES (v_tx, b, 'debtor', 100);
        SET CONSTRAINTS ALL IMMEDIATE;
        RAISE EXCEPTION 'ASSERT duplicate identity accepted';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM LIKE '%only once%' THEN
                RAISE EXCEPTION 'ACCEPTANCE_OK duplicate rejected: %', SQLERRM;
            END IF;
            RAISE EXCEPTION 'ACCEPTANCE_FAIL unexpected error: %', SQLERRM;
    END;

    RAISE EXCEPTION 'ASSERT unreachable';
END;
$$;
