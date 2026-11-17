BEGIN;
CREATE TABLE public.expense_change_outputs (
  transaction_id uuid PRIMARY KEY REFERENCES public.transactions(id) ON DELETE RESTRICT,
  change_id uuid NOT NULL REFERENCES public.expense_change_results(change_id) ON DELETE RESTRICT,
  role text NOT NULL CHECK(role IN ('reversal','replacement'))
);
CREATE INDEX ON public.expense_change_outputs(change_id);
ALTER TABLE public.expense_change_outputs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.expense_change_outputs FROM PUBLIC,anon,authenticated;
INSERT INTO public.expense_change_outputs(transaction_id,change_id,role)
  SELECT reversal_id,change_id,'reversal' FROM public.expense_change_results WHERE reversal_id IS NOT NULL
  UNION ALL SELECT replacement_id,change_id,'replacement' FROM public.expense_change_results WHERE replacement_id IS NOT NULL;

CREATE FUNCTION public.record_expense_change_outputs() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  IF NEW.reversal_id IS NOT NULL THEN
    INSERT INTO public.expense_change_outputs VALUES(NEW.reversal_id,NEW.change_id,'reversal');
  END IF;
  IF NEW.replacement_id IS NOT NULL THEN
    INSERT INTO public.expense_change_outputs VALUES(NEW.replacement_id,NEW.change_id,'replacement');
  END IF;
  UPDATE public.reminders SET status='cancelled' WHERE transaction_id=NEW.transaction_id AND status='scheduled';
  UPDATE public.push_delivery_jobs j SET status='cancelled',lease_id=NULL,lease_until=NULL
    FROM public.notifications n WHERE j.notification_id=n.id AND n.related_transaction_id=NEW.transaction_id
      AND j.status IN ('pending','sending');
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.record_expense_change_outputs() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER record_expense_change_outputs AFTER INSERT ON public.expense_change_results
  FOR EACH ROW EXECUTE FUNCTION public.record_expense_change_outputs();

-- PostgREST computed field. The unnamed row parameter is not an RPC argument.
-- Only its ID is used; authorization is checked against stored rows.
CREATE FUNCTION public.expense_revision(public.transactions) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor uuid:=auth.uid(); result jsonb; parent jsonb;
BEGIN
  IF actor IS NULL OR NOT EXISTS(SELECT 1 FROM public.transactions t
    JOIN public.transaction_participants s ON s.transaction_id=t.id
    WHERE t.id=($1).id AND s.user_id=actor AND public.is_tab_member(t.tab_id,actor)) THEN RETURN NULL; END IF;
  SELECT value INTO result FROM (
    SELECT 0 priority,jsonb_build_object('change_id',r.id,'original_id',r.transaction_id,
      'role','original','kind',r.kind,'reason',r.reason) value
      FROM public.expense_change_results z JOIN public.expense_change_requests r ON r.id=z.change_id
      WHERE z.transaction_id=($1).id
    UNION ALL
    SELECT 1,jsonb_build_object('change_id',r.id,'original_id',r.transaction_id,
      'role',o.role,'kind',r.kind,'reason',r.reason)
      FROM public.expense_change_outputs o JOIN public.expense_change_requests r ON r.id=o.change_id
      WHERE o.transaction_id=($1).id
  ) refs ORDER BY priority LIMIT 1;
  SELECT jsonb_build_object('parent_change_id',r.id,'parent_original_id',r.transaction_id)
    INTO parent FROM public.expense_change_outputs o JOIN public.expense_change_requests r ON r.id=o.change_id
    WHERE o.transaction_id=($1).id;
  IF parent IS NOT NULL THEN result:=result||parent; END IF;
  RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.expense_revision(public.transactions) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.expense_revision(public.transactions) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
