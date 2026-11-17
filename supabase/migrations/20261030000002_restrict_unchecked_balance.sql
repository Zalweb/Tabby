-- The unchecked balance helper has no membership check, so it must not be
-- callable by signed-in clients; trigger functions run it as the definer.
REVOKE ALL ON FUNCTION public.calculate_user_tab_balance_unchecked(UUID, UUID)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.calculate_user_tab_balance_unchecked(UUID, UUID)
    TO service_role;
