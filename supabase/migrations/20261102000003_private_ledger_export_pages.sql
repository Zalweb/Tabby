BEGIN;
-- No target-account argument: the server chooses scope from the JWT subject.
-- Explicit projections avoid exporting storage URLs or newly added columns.
CREATE OR REPLACE FUNCTION public.export_ledger_page_v1(
  p_section text, p_after uuid DEFAULT NULL, p_limit integer DEFAULT 50
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public AS $$
DECLARE actor uuid := auth.uid(); rows jsonb; last_id uuid; has_more boolean;
BEGIN
  IF actor IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;
  IF p_section IS NULL OR p_section NOT IN ('tabs', 'expenses', 'shares', 'payments')
    OR p_limit IS NULL OR p_limit < 1 OR p_limit > 100 THEN
    RAISE EXCEPTION 'Invalid export section or page size' USING ERRCODE = '22023';
  END IF;
  WITH authorized_tabs AS (
    SELECT t.id FROM public.tabs t
    WHERE t.user_a = actor OR t.user_b = actor OR EXISTS (
      SELECT 1 FROM public.tab_members m WHERE m.tab_id = t.id AND m.user_id = actor)
  ), scoped AS (
    SELECT t.id, jsonb_build_object('id',t.id, 'type',t.tab_type,
      'status',t.status, 'group_id',t.group_id, 'user_a',t.user_a,
      'user_b',t.user_b, 'created_at',t.created_at) AS record
    FROM public.tabs t JOIN authorized_tabs a ON a.id = t.id
    WHERE p_section = 'tabs'
    UNION ALL
    SELECT t.id, jsonb_build_object('id',t.id, 'tab_id',t.tab_id,
      'created_by',t.created_by, 'description',t.description,
      'category',t.category, 'status',t.status, 'total_amount_centavos',t.total_amount_centavos,
      'currency',t.currency, 'transaction_date',t.transaction_date,
      'due_date',t.due_date, 'created_at',t.created_at)
    FROM public.transactions t JOIN authorized_tabs a ON a.id = t.tab_id
    WHERE p_section = 'expenses'
    UNION ALL
    SELECT s.id, jsonb_build_object('id',s.id, 'transaction_id',s.transaction_id,
      'user_id',s.user_id, 'contact_id',s.contact_id,
      'role',s.participant_role, 'share_amount_centavos',s.share_amount_centavos,
      'acknowledged',s.acknowledged, 'acknowledged_at',s.acknowledged_at)
    FROM public.transaction_participants s
    JOIN public.transactions t ON t.id = s.transaction_id
    JOIN authorized_tabs a ON a.id = t.tab_id
    WHERE p_section = 'shares'
    UNION ALL
    SELECT p.id, jsonb_build_object('id',p.id, 'tab_id',p.tab_id,
      'submitted_by',p.submitted_by, 'recipient_user_id',p.recipient_user_id,
      'amount_centavos',p.amount_centavos, 'payment_method',p.payment_method,
      'note',p.note, 'status',p.status, 'submitted_at',p.submitted_at,
      'confirmed_by',p.confirmed_by, 'confirmed_at',p.confirmed_at)
    FROM public.payments p JOIN authorized_tabs a ON a.id = p.tab_id
    WHERE p_section = 'payments'
  ), page_window AS (
    SELECT * FROM scoped WHERE p_after IS NULL OR id > p_after
    ORDER BY id LIMIT p_limit + 1
  ), page AS (
    SELECT * FROM page_window ORDER BY id LIMIT p_limit
  )
  SELECT COALESCE((SELECT jsonb_agg(record ORDER BY id) FROM page),'[]'::jsonb),
    (SELECT id FROM page ORDER BY id DESC LIMIT 1),
    (SELECT count(*) > p_limit FROM page_window)
  INTO rows, last_id, has_more;
  RETURN jsonb_build_object('version',1, 'account_id',actor,
    'section',p_section, 'records',rows,
    'next_cursor',CASE WHEN has_more THEN last_id ELSE NULL END,
    'generated_at',statement_timestamp(),
    'consistency','Each page is a current read, not a whole-export snapshot.');
END $$;
REVOKE ALL ON FUNCTION public.export_ledger_page_v1(text,uuid,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.export_ledger_page_v1(text,uuid,integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_account_deletion_request_v1()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public AS $$
DECLARE actor uuid := auth.uid(); result jsonb;
BEGIN
  IF actor IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;
  SELECT jsonb_build_object('id',r.id,'account_id',actor,
    'requested_at',r.requested_at,'status',r.status)
  INTO result FROM public.account_deletion_requests r WHERE r.user_id = actor;
  RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_account_deletion_request_v1() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_account_deletion_request_v1() TO authenticated;
COMMIT;
