-- Tabby Database Migration: 20260917000004_relationship_scope.sql
-- Description: Keep unregistered contacts tab-only and restrict group rosters to
-- accepted friend relationships.

-- This helper is security-definer because group membership policies may need to
-- verify the relationship between a group creator and a prospective member.
CREATE OR REPLACE FUNCTION public.is_accepted_friend(
    p_user_a UUID,
    p_user_b UUID
)
RETURNS BOOLEAN AS $$
BEGIN
    IF p_user_a IS NULL OR p_user_b IS NULL OR p_user_a = p_user_b THEN
        RETURN FALSE;
    END IF;

    RETURN EXISTS (
        SELECT 1
        FROM public.friendships f
        WHERE f.status = 'accepted'
          AND (
              (f.requester_id = p_user_a AND f.addressee_id = p_user_b)
              OR (f.requester_id = p_user_b AND f.addressee_id = p_user_a)
          )
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public, pg_temp;

-- A group is a social context for registered, accepted friends only. The
-- creator is always allowed as the first member; pending, declined, blocked,
-- and unregistered contacts cannot be added to the group roster.
DROP POLICY IF EXISTS "Group admins or creator can add members" ON public.group_members;
CREATE POLICY "Group admins or creator can add members"
    ON public.group_members FOR INSERT
    TO authenticated
    WITH CHECK (
        (
            public.is_group_admin(group_id, auth.uid())
            OR (
                user_id = auth.uid()
                AND EXISTS (
                    SELECT 1
                    FROM public.groups g
                    WHERE g.id = group_id
                      AND g.created_by = auth.uid()
                )
            )
        )
        AND EXISTS (
            SELECT 1
            FROM public.groups g
            WHERE g.id = group_id
              AND (
                  user_id = g.created_by
                  OR public.is_accepted_friend(g.created_by, user_id)
              )
        )
    );

DROP POLICY IF EXISTS "Group admins can update members or user can leave" ON public.group_members;
CREATE POLICY "Group admins can update members or user can leave"
    ON public.group_members FOR UPDATE
    TO authenticated
    USING (public.is_group_admin(group_id, auth.uid()) OR user_id = auth.uid())
    WITH CHECK (
        (
            public.is_group_admin(group_id, auth.uid())
            OR user_id = auth.uid()
        )
        AND EXISTS (
            SELECT 1
            FROM public.groups g
            WHERE g.id = group_id
              AND (
                  user_id = g.created_by
                  OR public.is_accepted_friend(g.created_by, user_id)
              )
        )
    );

-- Individual tabs may still contain contact_id-only participants. Group tabs
-- may contain only the group creator and that creator's accepted friends.
DROP POLICY IF EXISTS "Tab members or creator can add tab members" ON public.tab_members;
CREATE POLICY "Tab members or creator can add tab members"
    ON public.tab_members FOR INSERT
    TO authenticated
    WITH CHECK (
        (
            EXISTS (
                SELECT 1
                FROM public.tab_members tm
                WHERE tm.tab_id = tab_id
                  AND tm.user_id = auth.uid()
                  AND tm.role = 'admin'
            )
            OR (
                user_id = auth.uid()
                AND EXISTS (
                    SELECT 1
                    FROM public.tabs t
                    JOIN public.groups g ON g.id = t.group_id
                    WHERE t.id = tab_id
                      AND g.created_by = auth.uid()
                )
            )
        )
        AND (
            NOT EXISTS (
                SELECT 1
                FROM public.tabs t
                WHERE t.id = tab_id
                  AND t.group_id IS NOT NULL
            )
            OR EXISTS (
                SELECT 1
                FROM public.tabs t
                JOIN public.groups g ON g.id = t.group_id
                WHERE t.id = tab_id
                  AND (
                      user_id = g.created_by
                      OR public.is_accepted_friend(g.created_by, user_id)
                  )
            )
        )
    );

-- Removing a friend ends the social relationship but intentionally leaves all
-- bilateral tabs, transactions, reminders, and audit history untouched.
CREATE OR REPLACE FUNCTION public.remove_friend(p_friend_user_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    IF p_friend_user_id IS NULL OR p_friend_user_id = auth.uid() THEN
        RETURN FALSE;
    END IF;

    DELETE FROM public.friendships f
    WHERE f.status = 'accepted'
      AND (
          (f.requester_id = auth.uid() AND f.addressee_id = p_friend_user_id)
          OR (f.requester_id = p_friend_user_id AND f.addressee_id = auth.uid())
      );

    RETURN FOUND;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

ALTER FUNCTION public.is_accepted_friend(UUID, UUID) SET search_path = public, pg_temp;
ALTER FUNCTION public.remove_friend(UUID) SET search_path = public, pg_temp;
REVOKE EXECUTE ON FUNCTION public.is_accepted_friend(UUID, UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.is_accepted_friend(UUID, UUID) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.remove_friend(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.remove_friend(UUID) TO authenticated;
