-- QR-002: row and private-object authorization share the same narrow contract.
-- Unchecked financial helpers remain inaccessible to mobile client roles.
BEGIN;

CREATE OR REPLACE FUNCTION public.can_read_payment_method(p_method_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, pg_temp AS $$
    SELECT auth.uid() IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.payment_methods pm
        WHERE pm.id = p_method_id AND (
            pm.owner_user_id = auth.uid()
            OR (pm.is_active AND (
                EXISTS (
                    SELECT 1 FROM public.friendships f WHERE f.status = 'accepted'
                    AND ((f.requester_id = auth.uid() AND f.addressee_id = pm.owner_user_id)
                      OR (f.addressee_id = auth.uid() AND f.requester_id = pm.owner_user_id))
                ) OR EXISTS (
                    SELECT 1 FROM public.tabs t
                    JOIN public.tab_members debtor ON debtor.tab_id = t.id AND debtor.user_id = auth.uid()
                    JOIN public.tab_members payee ON payee.tab_id = t.id AND payee.user_id = pm.owner_user_id
                    WHERE t.status = 'active'
                      AND public.get_pair_outstanding(t.id, auth.uid(), pm.owner_user_id) > 0
                )
            ))
        )
    );
$$;

CREATE OR REPLACE FUNCTION public.can_read_payment_method_file(p_name TEXT)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, pg_temp AS $$
    SELECT auth.uid() IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.payment_methods pm
        WHERE pm.qr_storage_path = p_name AND pm.is_active
          AND public.can_read_payment_method(pm.id)
    );
$$;

REVOKE ALL ON FUNCTION public.can_read_payment_method(UUID),
    public.can_read_payment_method_file(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_read_payment_method(UUID),
    public.can_read_payment_method_file(TEXT) TO authenticated;
GRANT SELECT ON public.payment_methods TO authenticated;

DROP POLICY IF EXISTS "Owners can view their payment methods" ON public.payment_methods;
CREATE POLICY "Authorized parties can view payment methods"
    ON public.payment_methods FOR SELECT TO authenticated
    USING (public.can_read_payment_method(id));

DROP POLICY IF EXISTS "Authorized debtors can view payment methods files" ON storage.objects;
CREATE POLICY "Authorized parties can view payment methods files"
    ON storage.objects FOR SELECT TO authenticated
    USING (bucket_id = 'payment-methods' AND public.can_read_payment_method_file(name));

CREATE OR REPLACE FUNCTION public.list_payment_methods_for_tab(
    p_tab_id UUID, p_payee_user_id UUID
)
RETURNS TABLE (
    id UUID, owner_user_id UUID, provider TEXT, display_name TEXT,
    account_label TEXT, qr_storage_path TEXT, is_active BOOLEAN,
    is_default BOOLEAN, created_at TIMESTAMPTZ, updated_at TIMESTAMPTZ
) LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, pg_temp AS $$
BEGIN
    IF auth.uid() IS NULL OR p_payee_user_id = auth.uid()
       OR NOT EXISTS (
            SELECT 1 FROM public.tabs t
            JOIN public.tab_members debtor ON debtor.tab_id = t.id AND debtor.user_id = auth.uid()
            JOIN public.tab_members payee ON payee.tab_id = t.id AND payee.user_id = p_payee_user_id
            WHERE t.id = p_tab_id AND t.status = 'active'
       ) OR public.get_pair_outstanding(p_tab_id, auth.uid(), p_payee_user_id) <= 0 THEN
        RETURN;
    END IF;
    RETURN QUERY SELECT pm.id, pm.owner_user_id, pm.provider, pm.display_name,
        pm.account_label, pm.qr_storage_path, pm.is_active, pm.is_default,
        pm.created_at, pm.updated_at
        FROM public.payment_methods pm
        WHERE pm.owner_user_id = p_payee_user_id AND pm.is_active
        ORDER BY pm.is_default DESC, pm.created_at, pm.id;
END;
$$;
REVOKE ALL ON FUNCTION public.list_payment_methods_for_tab(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_payment_methods_for_tab(UUID, UUID) TO authenticated;
COMMIT;
