BEGIN;
CREATE INDEX IF NOT EXISTS transactions_tab_page ON public.transactions(tab_id,id);
CREATE INDEX IF NOT EXISTS payments_tab_page ON public.payments(tab_id,id);

CREATE FUNCTION public.get_tab_balances_v1(p_tab_ids uuid[]) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor uuid:=auth.uid(); result jsonb;
BEGIN
  IF actor IS NULL OR cardinality(p_tab_ids) IS NULL OR cardinality(p_tab_ids) NOT BETWEEN 1 AND 100
    OR array_position(p_tab_ids,NULL) IS NOT NULL THEN
    RAISE EXCEPTION 'Invalid authenticated tab batch' USING ERRCODE='22023';
  END IF;
  IF EXISTS(SELECT 1 FROM unnest(p_tab_ids) id WHERE NOT public.is_tab_member(id,actor)) THEN
    RAISE EXCEPTION 'Not authorized for every requested tab' USING ERRCODE='42501';
  END IF;
  SELECT jsonb_agg(jsonb_build_object('tab_id',id,'net_balance_centavos',
    public.calculate_user_tab_balance_unchecked(id,actor)) ORDER BY id)
    INTO result FROM (SELECT DISTINCT unnest(p_tab_ids) id) ids;
  RETURN jsonb_build_object('version',1,'account_id',actor,'balances',result);
END $$;

CREATE FUNCTION public.get_tab_ledger_page_v1(p_tab_ids uuid[],p_kind text,
  p_after uuid DEFAULT NULL,p_limit integer DEFAULT 200) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor uuid:=auth.uid(); result jsonb; last_id uuid; more boolean;
BEGIN
  IF actor IS NULL OR cardinality(p_tab_ids) IS NULL OR cardinality(p_tab_ids) NOT BETWEEN 1 AND 100
    OR array_position(p_tab_ids,NULL) IS NOT NULL OR p_kind IS NULL OR p_kind NOT IN ('transactions','payments')
    OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 200 THEN
    RAISE EXCEPTION 'Invalid authenticated history page' USING ERRCODE='22023';
  END IF;
  IF EXISTS(SELECT 1 FROM unnest(p_tab_ids) id WHERE NOT public.is_tab_member(id,actor)) THEN
    RAISE EXCEPTION 'Not authorized for every requested tab' USING ERRCODE='42501';
  END IF;
  IF p_kind='transactions' THEN
    WITH page_window AS (SELECT t.* FROM public.transactions t
      WHERE t.tab_id=ANY(p_tab_ids) AND (p_after IS NULL OR t.id>p_after)
      ORDER BY t.id LIMIT p_limit+1), page AS (SELECT * FROM page_window ORDER BY id LIMIT p_limit)
    SELECT COALESCE(jsonb_agg(jsonb_build_object('id',t.id,'tab_id',t.tab_id,
      'created_by',t.created_by,'transaction_type',t.transaction_type,'category',t.category,
      'description',t.description,'total_amount_centavos',t.total_amount_centavos,
      'currency',t.currency,'due_date',t.due_date,'status',t.status,'created_at',t.created_at,
      'receipt_url',t.receipt_url,'expense_revision',public.expense_revision(ROW(t.*)::public.transactions),
      'transaction_receipt_revisions',COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'storage_path',r.storage_path,'uploaded_at',r.uploaded_at) ORDER BY r.uploaded_at,r.id)
        FROM public.transaction_receipt_revisions r WHERE r.transaction_id=t.id),'[]'::jsonb),
      'transaction_participants',COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'user_id',s.user_id,'contact_id',s.contact_id,'participant_role',s.participant_role,
        'share_amount_centavos',s.share_amount_centavos,'acknowledged',s.acknowledged) ORDER BY s.id)
        FROM public.transaction_participants s WHERE s.transaction_id=t.id),'[]'::jsonb)) ORDER BY t.id),'[]'::jsonb),
      (SELECT id FROM page ORDER BY id DESC LIMIT 1),(SELECT count(*)>p_limit FROM page_window)
      INTO result,last_id,more FROM page t;
  ELSE
    WITH page_window AS (SELECT p.* FROM public.payments p
      WHERE p.tab_id=ANY(p_tab_ids) AND (p_after IS NULL OR p.id>p_after)
      ORDER BY p.id LIMIT p_limit+1), page AS (SELECT * FROM page_window ORDER BY id LIMIT p_limit)
    SELECT COALESCE(jsonb_agg(jsonb_build_object('id',p.id,'tab_id',p.tab_id,
      'submitted_by',p.submitted_by,'payer_user_id',p.payer_user_id,'payer_contact_id',p.payer_contact_id,
      'recipient_user_id',p.recipient_user_id,'recipient_contact_id',p.recipient_contact_id,
      'amount_centavos',p.amount_centavos,'payment_method',p.payment_method,'note',p.note,
      'rejection_reason',p.rejection_reason,'status',p.status,'submitted_at',p.submitted_at,
      'payment_proofs',COALESCE((SELECT jsonb_agg(jsonb_build_object('file_url',f.file_url,
        'reference',f.reference,'uploaded_at',f.uploaded_at) ORDER BY f.uploaded_at,f.id)
        FROM public.payment_proofs f WHERE f.payment_id=p.id),'[]'::jsonb)) ORDER BY p.id),'[]'::jsonb),
      (SELECT id FROM page ORDER BY id DESC LIMIT 1),(SELECT count(*)>p_limit FROM page_window)
      INTO result,last_id,more FROM page p;
  END IF;
  RETURN jsonb_build_object('version',1,'account_id',actor,'kind',p_kind,'records',result,
    'next_cursor',CASE WHEN more THEN last_id ELSE NULL END);
END $$;
REVOKE ALL ON FUNCTION public.get_tab_balances_v1(uuid[]),public.get_tab_ledger_page_v1(uuid[],text,uuid,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_tab_balances_v1(uuid[]),public.get_tab_ledger_page_v1(uuid[],text,uuid,integer) TO authenticated;
COMMIT;
