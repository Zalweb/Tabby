-- Acceptance: authorization boundaries S1-S4 and S7 from
-- security_best_practices_report.md.
--
-- Everything runs inside one transaction that ends with ROLLBACK, so the
-- fixture users, tabs, transaction and storage objects never persist. Checks
-- execute as the `authenticated` role with a forged JWT subject, which is the
-- only way RLS is actually enforced. A passing run reports AUTHZ_ACCEPTANCE_OK.

BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.expect(label text, actual bigint, expected bigint)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF actual IS DISTINCT FROM expected THEN
        RAISE EXCEPTION 'AUTHZ_FAIL %: expected %, got %', label, expected, actual;
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Fixtures (owner role bypasses RLS)
--   A = authenticated subject under test
--   B = connected counterpart of A in TAB_AB
--   C = stranger, no relationship with A
--   TAB_AB     A admin,    B participant
--   TAB_B_ONLY B admin,    A not a member
--   TAB_A_PART B admin,    A participant
-- ---------------------------------------------------------------------------
-- public.users.id is FK-bound to auth.users, so the auth rows come first. Both
-- inserts roll back with the rest of the script.
INSERT INTO auth.users (id) VALUES
    ('00000000-0000-4000-8000-00000000a001'),
    ('00000000-0000-4000-8000-00000000b002'),
    ('00000000-0000-4000-8000-00000000c003')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.users (id, display_name, email) VALUES
    ('00000000-0000-4000-8000-00000000a001', 'Authz Alpha',   'authz-alpha@example.test'),
    ('00000000-0000-4000-8000-00000000b002', 'Authz Bravo',   'authz-bravo@example.test'),
    ('00000000-0000-4000-8000-00000000c003', 'Authz Charlie', 'authz-charlie@example.test')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.tabs (id, tab_type, status, user_a) VALUES
    ('00000000-0000-4000-8000-00000000ab01', 'individual', 'active', '00000000-0000-4000-8000-00000000a001'),
    ('00000000-0000-4000-8000-00000000b001', 'individual', 'active', '00000000-0000-4000-8000-00000000b002'),
    ('00000000-0000-4000-8000-00000000ac01', 'individual', 'active', '00000000-0000-4000-8000-00000000b002')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.tab_members (tab_id, user_id, role) VALUES
    ('00000000-0000-4000-8000-00000000ab01', '00000000-0000-4000-8000-00000000a001', 'admin'),
    ('00000000-0000-4000-8000-00000000ab01', '00000000-0000-4000-8000-00000000b002', 'participant'),
    ('00000000-0000-4000-8000-00000000b001', '00000000-0000-4000-8000-00000000b002', 'admin'),
    ('00000000-0000-4000-8000-00000000ac01', '00000000-0000-4000-8000-00000000b002', 'admin'),
    ('00000000-0000-4000-8000-00000000ac01', '00000000-0000-4000-8000-00000000a001', 'participant');

INSERT INTO public.transactions (id, tab_id, created_by, description, total_amount_centavos, receipt_url) VALUES
    ('00000000-0000-4000-8000-00000000e101', '00000000-0000-4000-8000-00000000ab01',
     '00000000-0000-4000-8000-00000000b002', 'Authz fixture expense', 10000, NULL),
    ('00000000-0000-4000-8000-00000000e102', '00000000-0000-4000-8000-00000000ab01',
     '00000000-0000-4000-8000-00000000a001', 'Authz linked proof', 5000,
     '00000000-0000-4000-8000-00000000b002/linked.png')
ON CONFLICT (id) DO NOTHING;

INSERT INTO storage.objects (id, bucket_id, name, owner) VALUES
    ('00000000-0000-4000-8000-00000000f001', 'payment-proofs', '00000000-0000-4000-8000-00000000a001/proof.png', '00000000-0000-4000-8000-00000000a001'),
    ('00000000-0000-4000-8000-00000000f002', 'payment-proofs', '00000000-0000-4000-8000-00000000c003/secret.png', '00000000-0000-4000-8000-00000000c003'),
    ('00000000-0000-4000-8000-00000000f003', 'payment-proofs', '00000000-0000-4000-8000-00000000b002/linked.png', '00000000-0000-4000-8000-00000000b002')
ON CONFLICT (id) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Act as user A.
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-00000000a001","role":"authenticated"}', true);

-- S1: profile enumeration.
SELECT pg_temp.expect('S1 own profile visible',
    (SELECT count(*) FROM public.users WHERE id = '00000000-0000-4000-8000-00000000a001'), 1);
SELECT pg_temp.expect('S1 connected profile visible',
    (SELECT count(*) FROM public.users WHERE id = '00000000-0000-4000-8000-00000000b002'), 1);
SELECT pg_temp.expect('S1 stranger profile hidden',
    (SELECT count(*) FROM public.users WHERE id = '00000000-0000-4000-8000-00000000c003'), 0);
SELECT pg_temp.expect('S1 open-ended profile sweep returns nothing',
    (SELECT count(*) FROM public.users
     WHERE id NOT IN ('00000000-0000-4000-8000-00000000a001',
                      '00000000-0000-4000-8000-00000000b002')), 0);

-- S2: payment-proof storage.
SELECT pg_temp.expect('S2 own object visible',
    (SELECT count(*) FROM storage.objects
     WHERE name = '00000000-0000-4000-8000-00000000a001/proof.png'), 1);
SELECT pg_temp.expect('S2 stranger object hidden',
    (SELECT count(*) FROM storage.objects
     WHERE name = '00000000-0000-4000-8000-00000000c003/secret.png'), 0);
SELECT pg_temp.expect('S2 counterpart object in shared tab visible',
    (SELECT count(*) FROM storage.objects
     WHERE name = '00000000-0000-4000-8000-00000000b002/linked.png'), 1);

DO $$
BEGIN
    INSERT INTO storage.objects (bucket_id, name)
    VALUES ('payment-proofs', '00000000-0000-4000-8000-00000000a001/own-upload.png');

    BEGIN
        INSERT INTO storage.objects (bucket_id, name)
        VALUES ('payment-proofs', '00000000-0000-4000-8000-00000000b002/forged.png');
        RAISE EXCEPTION 'S2_FAIL upload into another user folder was allowed';
    EXCEPTION WHEN insufficient_privilege THEN
        NULL;
    END;
END $$;

-- S3: membership management.
DO $$
BEGIN
    INSERT INTO public.tab_members (tab_id, user_id, role)
    VALUES ('00000000-0000-4000-8000-00000000ab01',
            '00000000-0000-4000-8000-00000000c003', 'participant');
END $$;

DO $$
DECLARE
    v_blocked BOOLEAN := FALSE;
BEGIN
    BEGIN
        INSERT INTO public.tab_members (tab_id, user_id, role)
        VALUES ('00000000-0000-4000-8000-00000000b001',
                '00000000-0000-4000-8000-00000000c003', 'participant');
    EXCEPTION WHEN insufficient_privilege THEN
        v_blocked := TRUE;
    END;
    IF NOT v_blocked THEN
        RAISE EXCEPTION 'S3_FAIL cross-tab membership insert was allowed';
    END IF;
END $$;

DO $$
DECLARE
    v_rows INTEGER;
BEGIN
    UPDATE public.tab_members SET role = 'admin'
    WHERE tab_id = '00000000-0000-4000-8000-00000000ac01'
      AND user_id = '00000000-0000-4000-8000-00000000b002';
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows <> 0 THEN
        RAISE EXCEPTION 'S3_FAIL non-admin membership update affected % rows', v_rows;
    END IF;

    DELETE FROM public.tab_members
    WHERE tab_id = '00000000-0000-4000-8000-00000000ac01'
      AND user_id = '00000000-0000-4000-8000-00000000b002';
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows <> 0 THEN
        RAISE EXCEPTION 'S3_FAIL non-admin removal affected % rows', v_rows;
    END IF;

    DELETE FROM public.tab_members
    WHERE tab_id = '00000000-0000-4000-8000-00000000ac01'
      AND user_id = '00000000-0000-4000-8000-00000000a001';
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows <> 1 THEN
        RAISE EXCEPTION 'S3_FAIL self-leave affected % rows', v_rows;
    END IF;
END $$;

-- S4: contact-tab RPC ownership.
DO $$
DECLARE
    v_allowed BOOLEAN := FALSE;
BEGIN
    BEGIN
        PERFORM public.get_or_create_contact_tab(
            '00000000-0000-4000-8000-00000000b002', 'Bravo Contact');
    EXCEPTION WHEN insufficient_privilege THEN
        v_allowed := TRUE;
    END;
    IF NOT v_allowed THEN
        RAISE EXCEPTION 'S4_FAIL owner spoofing was allowed';
    END IF;

    BEGIN
        PERFORM public.get_or_create_contact_tab(
            '00000000-0000-4000-8000-00000000a001', 'Alpha Contact');
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'S4_FAIL own contact tab call failed: %', SQLERRM;
    END;
END $$;

-- S7: receipt reference guard.
DO $$
DECLARE
    v_rows INTEGER;
BEGIN
    UPDATE public.transactions
    SET receipt_url = '00000000-0000-4000-8000-00000000a001/proof.png'
    WHERE id = '00000000-0000-4000-8000-00000000e101';
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows <> 1 THEN
        RAISE EXCEPTION 'S7_FAIL uploader-owned receipt path was blocked';
    END IF;

    BEGIN
        UPDATE public.transactions
        SET receipt_url = '00000000-0000-4000-8000-00000000b002/foreign.png'
        WHERE id = '00000000-0000-4000-8000-00000000e101';
        RAISE EXCEPTION 'S7_FAIL foreign receipt path was allowed';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM NOT LIKE '%belong to the uploader%' THEN
            RAISE;
        END IF;
    END;

    BEGIN
        UPDATE public.transactions
        SET receipt_url = 'https://evil.example/proof.png'
        WHERE id = '00000000-0000-4000-8000-00000000e101';
        RAISE EXCEPTION 'S7_FAIL remote receipt URL was allowed';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM NOT LIKE '%uploaded files%' THEN
            RAISE;
        END IF;
    END;
END $$;

RESET ROLE;
SELECT 'AUTHZ_ACCEPTANCE_OK' AS result;

ROLLBACK;
