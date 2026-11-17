-- SEC-002: this unchecked balance helper is an internal implementation detail.
-- SECURITY DEFINER payment RPCs execute it as their owner after authorizing
-- the caller. Mobile clients never call this function directly.
REVOKE ALL ON FUNCTION public.get_pair_outstanding(UUID, UUID, UUID)
    FROM PUBLIC, anon, authenticated;
