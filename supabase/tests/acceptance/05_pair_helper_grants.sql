-- Run after all migrations, as database owner. No data mutations.
-- This tests effective privileges, including PUBLIC/inherited grants.
BEGIN;
DO $$
DECLARE
    client_role text;
BEGIN
    FOREACH client_role IN ARRAY ARRAY['anon', 'authenticated'] LOOP
        IF has_function_privilege(client_role,
            'public.get_pair_outstanding(uuid,uuid,uuid)', 'EXECUTE') THEN
            RAISE EXCEPTION 'PAIR_HELPER_FAIL: % can execute unchecked helper', client_role;
        END IF;
    END LOOP;
    IF NOT has_function_privilege(current_user,
        'public.get_pair_outstanding(uuid,uuid,uuid)', 'EXECUTE') THEN
        RAISE EXCEPTION 'PAIR_HELPER_FAIL: owner cannot execute helper';
    END IF;
END $$;
SELECT 'PAIR_HELPER_GRANTS_OK';
ROLLBACK;
