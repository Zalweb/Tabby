ALTER TABLE public.payments ADD COLUMN rejection_reason TEXT;
ALTER TABLE public.payments ADD COLUMN rejected_at TIMESTAMPTZ;
CREATE TABLE public.payment_decisions (
  payment_id UUID PRIMARY KEY REFERENCES public.payments(id) ON DELETE RESTRICT,
  actor_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  decision TEXT NOT NULL CHECK(decision IN ('confirmed','rejected')),
  reason TEXT,
  decided_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.payment_decisions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.payment_decisions FROM PUBLIC,anon,authenticated;
REVOKE UPDATE,DELETE ON public.payments FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.decide_payment_internal(p_payment_id UUID,p_confirm BOOLEAN,p_reason TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  v_actor UUID:=auth.uid();
  v_payment public.payments%ROWTYPE;
  v_tab UUID;
  v_outstanding BIGINT;
BEGIN
  IF v_actor IS NULL OR p_confirm IS NULL THEN
    RAISE EXCEPTION 'Authentication and decision required' USING ERRCODE='42501';
  END IF;
  SELECT tab_id INTO v_tab FROM public.payments WHERE id=p_payment_id;
  IF v_tab IS NULL THEN RAISE EXCEPTION 'Payment unavailable' USING ERRCODE='42501'; END IF;
  -- Same lock as submission/overpayment triggers. Acquire before the row lock
  -- and balance read so different pending rows cannot use the same balance.
  PERFORM pg_advisory_xact_lock(hashtextextended(v_tab::TEXT,0));
  SELECT * INTO v_payment FROM public.payments WHERE id=p_payment_id FOR UPDATE;
  IF v_payment.recipient_user_id IS DISTINCT FROM v_actor
     OR NOT public.is_tab_member(v_tab,v_actor) THEN
    RAISE EXCEPTION 'Only the recipient can decide this payment' USING ERRCODE='42501';
  END IF;
  IF p_confirm AND v_payment.status='confirmed' THEN RETURN p_payment_id; END IF;
  IF NOT p_confirm AND v_payment.status='rejected' AND
      v_payment.rejection_reason IS NOT DISTINCT FROM nullif(trim(p_reason),'') THEN RETURN p_payment_id; END IF;
  IF v_payment.status<>'submitted' THEN
    RAISE EXCEPTION 'Payment already has a different decision' USING ERRCODE='22023';
  END IF;
  IF p_confirm THEN
    v_outstanding:=public.get_party_outstanding_internal(v_tab,'user',
      COALESCE(v_payment.payer_user_id,v_payment.submitted_by),'user',v_actor);
    IF v_payment.amount_centavos>v_outstanding OR v_outstanding<=0 THEN
      RAISE EXCEPTION 'Payment exceeds remaining pair obligation' USING ERRCODE='22023';
    END IF;
    INSERT INTO public.payment_decisions(payment_id,actor_id,decision)
      VALUES(p_payment_id,v_actor,'confirmed');
    UPDATE public.payments SET status='confirmed',confirmed_by=v_actor,confirmed_at=now()
      WHERE id=p_payment_id;
  ELSE
    IF nullif(trim(p_reason),'') IS NULL OR length(p_reason)>500 THEN
      RAISE EXCEPTION 'A rejection reason of 1 to 500 characters is required' USING ERRCODE='22023';
    END IF;
    INSERT INTO public.payment_decisions(payment_id,actor_id,decision,reason)
      VALUES(p_payment_id,v_actor,'rejected',trim(p_reason));
    UPDATE public.payments SET status='rejected',rejection_reason=trim(p_reason),rejected_at=now()
      WHERE id=p_payment_id;
  END IF;
  RETURN p_payment_id;
END; $$;
REVOKE ALL ON FUNCTION public.decide_payment_internal(UUID,BOOLEAN,TEXT) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.confirm_payment(p_payment_id UUID)
RETURNS UUID LANGUAGE sql SECURITY DEFINER SET search_path=public,pg_temp AS $$
  SELECT public.decide_payment_internal(p_payment_id,true,NULL);
$$;
CREATE FUNCTION public.reject_payment_v1(p_payment_id UUID,p_reason TEXT)
RETURNS UUID LANGUAGE sql SECURITY DEFINER SET search_path=public,pg_temp AS $$
  SELECT public.decide_payment_internal(p_payment_id,false,p_reason);
$$;
REVOKE ALL ON FUNCTION public.confirm_payment(UUID),public.reject_payment_v1(UUID,TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.confirm_payment(UUID),public.reject_payment_v1(UUID,TEXT) TO authenticated;

CREATE FUNCTION public.require_explicit_wallet_confirmation()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
  IF NEW.status='confirmed' AND NEW.payment_method<>'cash' THEN
    RAISE EXCEPTION 'Wallet payments require submission and a specific recipient decision' USING ERRCODE='22023';
  END IF;
  RETURN NEW;
END; $$;
REVOKE ALL ON FUNCTION public.require_explicit_wallet_confirmation() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER require_explicit_wallet_confirmation BEFORE INSERT ON public.payments
  FOR EACH ROW EXECUTE FUNCTION public.require_explicit_wallet_confirmation();
