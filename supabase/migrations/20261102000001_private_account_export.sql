-- Intentionally limited personal-data export. Shared ledger/media need a
-- separate paginated export contract; do not expose arbitrary row JSON.
BEGIN;
CREATE OR REPLACE FUNCTION public.export_account_data_v1()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public AS $$
DECLARE actor uuid := auth.uid(); result jsonb;
BEGIN
  IF actor IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;
  SELECT jsonb_build_object(
    'version', 1, 'account_id', actor, 'generated_at', statement_timestamp(),
    'scope', 'profile_and_owned_contacts',
    'excluded', jsonb_build_array('shared_ledger', 'payment_methods',
      'media', 'notifications', 'authentication_records', 'local_drafts'),
    'profile', (SELECT jsonb_build_object(
      'id', u.id, 'display_name', u.display_name, 'email', u.email,
      'phone', u.phone, 'created_at', u.created_at)
      FROM public.users u WHERE u.id = actor),
    'contacts', COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id', c.id, 'display_name', c.display_name, 'email', c.email,
      'phone', c.phone, 'created_at', c.created_at) ORDER BY c.id)
      FROM public.contacts c WHERE c.owner_user_id = actor), '[]'::jsonb)
  ) INTO result;
  RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.export_account_data_v1() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.export_account_data_v1() TO authenticated;
COMMIT;
