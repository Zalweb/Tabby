-- Acceptance: expense -> debtor notification -> payment -> confirmation -> reminder.
-- Requires at least two existing users. The script always ends with an exception so
-- every write it performs is rolled back; a passing run reports ACCEPTANCE_OK.
DO $$
DECLARE
    a UUID;
    b UUID;
    v_tab UUID := gen_random_uuid();
    v_tx UUID;
    v_pay UUID;
    v_out BIGINT;
    v_notif INTEGER;
    v_log INTEGER;
    v_status TEXT;
    v_recipient UUID;
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
        v_tab, 'Acceptance expense', 'food', 10000, a,
        jsonb_build_array(
            jsonb_build_object('user_id', a, 'participant_role', 'payer',
                               'share_amount_centavos', 5000, 'acknowledged', true),
            jsonb_build_object('user_id', b, 'participant_role', 'debtor',
                               'share_amount_centavos', 5000, 'acknowledged', false)
        ), NULL, NULL);

    IF v_tx IS NULL THEN RAISE EXCEPTION 'ASSERT expense not created'; END IF;

    SELECT count(*) INTO v_notif FROM public.notifications
    WHERE related_transaction_id = v_tx
      AND notification_type = 'expense_added'
      AND recipient_user_id = b;
    IF v_notif <> 1 THEN
        RAISE EXCEPTION 'ASSERT expected 1 expense_added notification, got %', v_notif;
    END IF;

    v_out := public.get_pair_outstanding(v_tab, b, a);
    IF v_out <> 5000 THEN RAISE EXCEPTION 'ASSERT outstanding expected 5000 got %', v_out; END IF;

    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', b, 'role', 'authenticated')::text, true);
    v_pay := public.submit_payment(v_tab, b, a, 5000, 'cash', 'acceptance');

    SELECT status, recipient_user_id INTO v_status, v_recipient
    FROM public.payments WHERE id = v_pay;
    IF v_status <> 'submitted' THEN RAISE EXCEPTION 'ASSERT payment status %', v_status; END IF;
    IF v_recipient <> a THEN RAISE EXCEPTION 'ASSERT payment recipient mismatch'; END IF;

    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', a, 'role', 'authenticated')::text, true);
    PERFORM public.confirm_payment(v_pay);

    v_out := public.get_pair_outstanding(v_tab, b, a);
    IF v_out <> 0 THEN
        RAISE EXCEPTION 'ASSERT outstanding after confirm expected 0 got %', v_out;
    END IF;

    PERFORM public.send_tab_reminder(v_tab, b, 'Acceptance reminder', 'Please settle');

    SELECT count(*) INTO v_notif FROM public.notifications
    WHERE related_tab_id = v_tab AND notification_type = 'tab_reminder';
    IF v_notif <> 1 THEN RAISE EXCEPTION 'ASSERT reminder notification %', v_notif; END IF;

    SELECT count(*) INTO v_log FROM public.activity_logs
    WHERE tab_id = v_tab AND event_type = 'REMINDER_SENT';
    IF v_log <> 1 THEN RAISE EXCEPTION 'ASSERT reminder activity log %', v_log; END IF;

    RAISE EXCEPTION 'ACCEPTANCE_OK expense=% payment=% outstanding_after_confirm=0 reminder=ok',
        v_tx, v_pay;
END;
$$;
