BEGIN;
CREATE TABLE public.account_deletion_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL UNIQUE REFERENCES public.users(id) ON DELETE RESTRICT,
  requested_at timestamptz NOT NULL DEFAULT now(),
  status text NOT NULL DEFAULT 'requested' CHECK (status IN ('requested', 'processing', 'completed'))
);
ALTER TABLE public.account_deletion_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.account_deletion_requests FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.account_deletion_requests TO authenticated;
CREATE POLICY read_own_deletion_request ON public.account_deletion_requests
  FOR SELECT TO authenticated USING (user_id = auth.uid());

CREATE OR REPLACE FUNCTION public.request_account_deletion_v1()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public AS $$
DECLARE actor uuid := auth.uid(); request public.account_deletion_requests;
BEGIN
  IF actor IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;
  -- AMR timestamps describe actual authentication, unlike refreshed-token iat.
  -- Claims come from the verified JWT at the PostgREST boundary.
  IF NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(COALESCE(auth.jwt()->'amr', '[]'::jsonb)) m
    WHERE m->>'method' IN ('password', 'otp', 'oauth', 'totp', 'sso/saml')
      AND CASE WHEN m->>'timestamp' ~ '^[0-9]{1,12}$'
        THEN (m->>'timestamp')::bigint
          BETWEEN extract(epoch FROM statement_timestamp())::bigint - 300
          AND extract(epoch FROM statement_timestamp())::bigint + 30
        ELSE false END
  ) THEN
    RAISE EXCEPTION 'Sign in again before requesting account deletion' USING ERRCODE = '42501';
  END IF;
  INSERT INTO public.account_deletion_requests(user_id) VALUES (actor)
    ON CONFLICT (user_id) DO NOTHING;
  SELECT * INTO STRICT request FROM public.account_deletion_requests WHERE user_id = actor;
  RETURN jsonb_build_object('id', request.id, 'account_id', actor,
    'requested_at', request.requested_at, 'status', request.status);
END $$;
REVOKE ALL ON FUNCTION public.request_account_deletion_v1() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_account_deletion_v1() TO authenticated;
-- This migration records a request only. It never deletes accounts, media or
-- financial history. A reviewed anonymization/retention processor is required.
COMMIT;
