-- Close the live authorization gaps reported in security_best_practices_report.md
-- (S1, S2, S3, S4, S7). The production project had drifted from the checked-in
-- policies: profile enumeration, bucket-wide proof storage, a cross-tab membership
-- tautology, an untracked SECURITY DEFINER RPC, and an unprotected receipt column.
-- Every object below is dropped first so this also replays cleanly on a fresh DB.

-- ======================================================================
-- S1: any signed-in user could read every profile row.
-- ======================================================================
DROP POLICY IF EXISTS "Users can view all registered user profiles" ON public.users;

-- ======================================================================
-- S2: payment-proof Storage was readable and writable bucket-wide.
-- Uploads must live under the uploader's own folder; reads are limited to
-- the uploader and members of the tab that references the object.
-- ======================================================================
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'storage' AND table_name = 'objects'
    ) THEN
        DROP POLICY IF EXISTS "Authenticated users can upload payment proofs" ON storage.objects;
        DROP POLICY IF EXISTS "Tab members can upload payment proofs" ON storage.objects;
        DROP POLICY IF EXISTS "Authenticated users can view payment proofs" ON storage.objects;
        DROP POLICY IF EXISTS "Uploaders can upload payment proofs" ON storage.objects;
        DROP POLICY IF EXISTS "Uploaders and tab counterparts can view payment proofs" ON storage.objects;

        CREATE POLICY "Uploaders can upload payment proofs"
            ON storage.objects FOR INSERT TO authenticated
            WITH CHECK (
                bucket_id = 'payment-proofs'
                AND (storage.foldername(name))[1] = auth.uid()::text
            );

        CREATE POLICY "Uploaders and tab counterparts can view payment proofs"
            ON storage.objects FOR SELECT TO authenticated
            USING (
                bucket_id = 'payment-proofs'
                AND (
                    (storage.foldername(name))[1] = auth.uid()::text
                    OR EXISTS (
                        SELECT 1 FROM public.transactions tx
                        WHERE tx.receipt_url = storage.objects.name
                          AND public.is_tab_member(tx.tab_id, auth.uid())
                    )
                )
            );
    END IF;
END $$;

-- ======================================================================
-- S3: the tab_members INSERT check compared tm.tab_id with itself, so an
-- admin of any tab could add members to any other tab. UPDATE and DELETE
-- only required membership, not admin status.
-- ======================================================================
DROP POLICY IF EXISTS "Tab members or creator can add tab members" ON public.tab_members;
DROP POLICY IF EXISTS "Tab admins or group creator can add tab members" ON public.tab_members;
CREATE POLICY "Tab admins or group creator can add tab members"
    ON public.tab_members FOR INSERT TO authenticated WITH CHECK (
        (
            EXISTS (
                SELECT 1 FROM public.tab_members admin
                WHERE admin.tab_id = tab_members.tab_id
                  AND admin.user_id = auth.uid()
                  AND admin.role = 'admin'
            )
            OR EXISTS (
                SELECT 1
                FROM public.tabs t
                JOIN public.groups g ON g.id = t.group_id
                WHERE t.id = tab_members.tab_id
                  AND g.created_by = auth.uid()
            )
        )
        AND (
            NOT EXISTS (
                SELECT 1 FROM public.tabs t
                WHERE t.id = tab_members.tab_id AND t.group_id IS NOT NULL
            )
            OR EXISTS (
                SELECT 1
                FROM public.tabs t
                JOIN public.groups g ON g.id = t.group_id
                WHERE t.id = tab_members.tab_id
                  AND (
                      tab_members.user_id = g.created_by
                      OR public.is_accepted_friend(g.created_by, tab_members.user_id)
                  )
            )
        )
    );

DROP POLICY IF EXISTS "Tab members can update tab membership" ON public.tab_members;
DROP POLICY IF EXISTS "Tab admins can update tab membership" ON public.tab_members;
CREATE POLICY "Tab admins can update tab membership"
    ON public.tab_members FOR UPDATE TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.tab_members admin
            WHERE admin.tab_id = tab_members.tab_id
              AND admin.user_id = auth.uid()
              AND admin.role = 'admin'
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.tab_members admin
            WHERE admin.tab_id = tab_members.tab_id
              AND admin.user_id = auth.uid()
              AND admin.role = 'admin'
        )
    );

DROP POLICY IF EXISTS "Tab members can remove members" ON public.tab_members;
DROP POLICY IF EXISTS "Tab admins or the member can remove membership" ON public.tab_members;
CREATE POLICY "Tab admins or the member can remove membership"
    ON public.tab_members FOR DELETE TO authenticated
    USING (
        user_id = auth.uid()
        OR EXISTS (
            SELECT 1 FROM public.tab_members admin
            WHERE admin.tab_id = tab_members.tab_id
              AND admin.user_id = auth.uid()
              AND admin.role = 'admin'
        )
    );

-- ======================================================================
-- S4: get_or_create_contact_tab was untracked in migrations, had no fixed
-- search_path, was executable by anon, and trusted a caller-supplied owner.
-- The client always calls it with its own id, so the owner check is safe.
-- ======================================================================
CREATE OR REPLACE FUNCTION public.get_or_create_contact_tab(
    p_owner_id uuid,
    p_contact_name text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
    v_contact_name TEXT := btrim(coalesce(p_contact_name, ''));
    v_contact_id UUID;
    v_tab_id UUID;
BEGIN
    IF auth.uid() IS NULL OR p_owner_id IS DISTINCT FROM auth.uid() THEN
        RAISE EXCEPTION 'Not authorized to create contact tabs for another user'
            USING ERRCODE = '42501';
    END IF;

    IF v_contact_name = '' THEN
        RAISE EXCEPTION 'Contact name is required' USING ERRCODE = '22023';
    END IF;

    SELECT id INTO v_contact_id
    FROM public.contacts
    WHERE owner_user_id = p_owner_id
      AND LOWER(display_name) = LOWER(v_contact_name)
    LIMIT 1;

    IF v_contact_id IS NULL THEN
        INSERT INTO public.contacts (owner_user_id, display_name)
        VALUES (p_owner_id, v_contact_name)
        RETURNING id INTO v_contact_id;
    END IF;

    SELECT tm.tab_id INTO v_tab_id
    FROM public.tab_members tm
    JOIN public.tabs t ON t.id = tm.tab_id
    WHERE tm.contact_id = v_contact_id
      AND t.tab_type = 'individual'
      AND t.status = 'active'
    LIMIT 1;

    IF v_tab_id IS NULL THEN
        INSERT INTO public.tabs (tab_type, status, user_a)
        VALUES ('individual', 'active', p_owner_id)
        RETURNING id INTO v_tab_id;

        INSERT INTO public.tab_members (tab_id, user_id, role)
        VALUES (v_tab_id, p_owner_id, 'admin');

        INSERT INTO public.tab_members (tab_id, contact_id, role)
        VALUES (v_tab_id, v_contact_id, 'participant');
    END IF;

    RETURN jsonb_build_object(
        'tab_id', v_tab_id,
        'contact_id', v_contact_id
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.get_or_create_contact_tab(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_or_create_contact_tab(uuid, text) TO authenticated;

-- ======================================================================
-- S7: transactions.receipt_url could be pointed at any value by any tab
-- member. New values must be files the caller uploaded, or a local path
-- used while offline. Remote URLs are rejected outright.
-- ======================================================================
CREATE OR REPLACE FUNCTION public.prevent_transaction_tampering()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
    v_uid TEXT := auth.uid()::text;
BEGIN
    IF NEW.tab_id IS DISTINCT FROM OLD.tab_id
       OR NEW.created_by IS DISTINCT FROM OLD.created_by
       OR NEW.recurring_rule_id IS DISTINCT FROM OLD.recurring_rule_id
       OR NEW.transaction_type IS DISTINCT FROM OLD.transaction_type
       OR NEW.category IS DISTINCT FROM OLD.category
       OR NEW.description IS DISTINCT FROM OLD.description
       OR NEW.total_amount_centavos IS DISTINCT FROM OLD.total_amount_centavos
       OR NEW.currency IS DISTINCT FROM OLD.currency
       OR NEW.transaction_date IS DISTINCT FROM OLD.transaction_date
       OR NEW.due_date IS DISTINCT FROM OLD.due_date
       OR NEW.status IS DISTINCT FROM OLD.status THEN
        RAISE EXCEPTION 'Financial transaction fields cannot be changed';
    END IF;

    IF NEW.receipt_url IS DISTINCT FROM OLD.receipt_url
       AND NEW.receipt_url IS NOT NULL
       AND NEW.receipt_url <> '' THEN
        IF NEW.receipt_url ~* '^[a-z]+://' AND NEW.receipt_url !~* '^(file|content)://' THEN
            RAISE EXCEPTION 'Receipt attachments must be uploaded files';
        END IF;

        IF v_uid IS NOT NULL
           AND NEW.receipt_url NOT LIKE v_uid || '/%'
           AND left(NEW.receipt_url, 1) <> '/'
           AND NEW.receipt_url !~* '^(file|content)://'
           AND NEW.receipt_url !~ '^[A-Za-z]:[\\/]' THEN
            RAISE EXCEPTION 'Receipt attachments must belong to the uploader';
        END IF;
    END IF;

    RETURN NEW;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.prevent_transaction_tampering() FROM PUBLIC, anon, authenticated;
