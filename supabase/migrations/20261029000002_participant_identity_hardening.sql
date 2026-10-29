-- Tabby Database Migration: 20261029000002_participant_identity_hardening.sql
-- Prevent duplicate identities and payer/debtor self-conflicts in allocations.

CREATE OR REPLACE FUNCTION public.validate_transaction_participant_identity()
RETURNS TRIGGER AS $$
BEGIN
    IF (NEW.user_id IS NULL) = (NEW.contact_id IS NULL) THEN
        RAISE EXCEPTION 'Each participant must identify exactly one user or contact';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.transaction_participants existing
        WHERE existing.transaction_id = NEW.transaction_id
          AND (
              (NEW.user_id IS NOT NULL AND existing.user_id = NEW.user_id)
              OR
              (NEW.contact_id IS NOT NULL AND existing.contact_id = NEW.contact_id)
          )
    ) THEN
        RAISE EXCEPTION 'A transaction participant identity may appear only once';
    END IF;

    IF NEW.participant_role = 'payer'
       AND EXISTS (
           SELECT 1
           FROM public.transaction_participants existing
           WHERE existing.transaction_id = NEW.transaction_id
             AND (
                 (NEW.user_id IS NOT NULL AND existing.user_id = NEW.user_id)
                 OR
                 (NEW.contact_id IS NOT NULL AND existing.contact_id = NEW.contact_id)
             )
       ) THEN
        RAISE EXCEPTION 'A payer cannot also be another participant';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql
SET search_path = public, pg_temp;

DROP TRIGGER IF EXISTS trigger_validate_transaction_participant_identity
    ON public.transaction_participants;
CREATE TRIGGER trigger_validate_transaction_participant_identity
    BEFORE INSERT ON public.transaction_participants
    FOR EACH ROW
    EXECUTE FUNCTION public.validate_transaction_participant_identity();

ALTER FUNCTION public.validate_transaction_participant_identity()
    SET search_path = public, pg_temp;

REVOKE ALL ON FUNCTION public.validate_transaction_participant_identity()
    FROM PUBLIC, anon;

-- A row-level BEFORE trigger cannot see rows inserted earlier in the same
-- multi-row statement, which is how create_expense_atomic writes participants.
-- Re-check the whole transaction at commit time to close that window.
CREATE OR REPLACE FUNCTION public.assert_transaction_participant_identities()
RETURNS TRIGGER AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM public.transaction_participants
        WHERE transaction_id = NEW.transaction_id
        GROUP BY user_id, contact_id
        HAVING count(*) > 1
    ) THEN
        RAISE EXCEPTION 'A transaction participant identity may appear only once';
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

ALTER FUNCTION public.assert_transaction_participant_identities()
    SET search_path = public, pg_temp;

REVOKE ALL ON FUNCTION public.assert_transaction_participant_identities()
    FROM PUBLIC, anon;

DROP TRIGGER IF EXISTS trigger_assert_transaction_participant_identities
    ON public.transaction_participants;
CREATE CONSTRAINT TRIGGER trigger_assert_transaction_participant_identities
    AFTER INSERT ON public.transaction_participants
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
    EXECUTE FUNCTION public.assert_transaction_participant_identities();
