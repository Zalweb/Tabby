-- Contact identity is explicit; display names are labels, never lookup keys.
CREATE FUNCTION public.resolve_contact_tab_v1(p_contact_id UUID, p_display_name TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_owner UUID := auth.uid(); v_existing_owner UUID; v_tab UUID;
BEGIN
    IF v_owner IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='42501'; END IF;
    IF p_contact_id IS NULL OR btrim(coalesce(p_display_name,'')) = '' THEN
        RAISE EXCEPTION 'Contact identity and display name required' USING ERRCODE='22023';
    END IF;
    IF EXISTS(SELECT 1 FROM public.users WHERE id=p_contact_id) THEN
      RAISE EXCEPTION 'Contact identity conflicts with a registered party' USING ERRCODE='22023';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtextextended(p_contact_id::TEXT, 0));
    SELECT owner_user_id INTO v_existing_owner FROM public.contacts WHERE id=p_contact_id;
    IF FOUND AND v_existing_owner IS DISTINCT FROM v_owner THEN
        RAISE EXCEPTION 'Contact belongs to another account' USING ERRCODE='42501';
    END IF;
    IF NOT FOUND THEN
        INSERT INTO public.contacts(id,owner_user_id,display_name)
        VALUES(p_contact_id,v_owner,btrim(p_display_name));
    END IF;
    SELECT tm.tab_id INTO v_tab FROM public.tab_members tm JOIN public.tabs t ON t.id=tm.tab_id
        WHERE tm.contact_id=p_contact_id AND t.tab_type='individual' AND t.status='active';
    IF v_tab IS NULL THEN
        INSERT INTO public.tabs(tab_type,status,user_a) VALUES('individual','active',v_owner) RETURNING id INTO v_tab;
        INSERT INTO public.tab_members(tab_id,user_id,role) VALUES(v_tab,v_owner,'admin');
        INSERT INTO public.tab_members(tab_id,contact_id,role) VALUES(v_tab,p_contact_id,'participant');
    END IF;
    RETURN jsonb_build_object('contact_id',p_contact_id,'tab_id',v_tab);
END; $$;
REVOKE ALL ON FUNCTION public.resolve_contact_tab_v1(UUID,TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.resolve_contact_tab_v1(UUID,TEXT) TO authenticated;
DO $$ BEGIN
  IF to_regprocedure('public.get_or_create_contact_tab(uuid,text)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.get_or_create_contact_tab(UUID,TEXT) FROM PUBLIC,anon,authenticated;
  END IF;
END; $$;

ALTER TABLE public.payments
    ADD COLUMN payer_user_id UUID REFERENCES public.users(id) ON DELETE RESTRICT,
    ADD COLUMN payer_contact_id UUID REFERENCES public.contacts(id) ON DELETE RESTRICT,
    ADD COLUMN recipient_contact_id UUID REFERENCES public.contacts(id) ON DELETE RESTRICT,
    ADD CONSTRAINT payment_payer_namespace CHECK (payer_contact_id IS NULL OR payer_user_id IS NULL),
    ADD CONSTRAINT payment_recipient_namespace CHECK (recipient_contact_id IS NULL OR recipient_user_id IS NULL);

CREATE OR REPLACE FUNCTION public.get_transaction_payer_id(p_transaction_id UUID)
RETURNS UUID LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public, pg_temp AS $$
    SELECT coalesce((SELECT coalesce(tp.user_id,tp.contact_id) FROM public.transaction_participants tp
      WHERE tp.transaction_id=p_transaction_id AND tp.participant_role='payer'),
      (SELECT created_by FROM public.transactions WHERE id=p_transaction_id));
$$;

CREATE FUNCTION public.get_party_outstanding_internal(p_tab UUID,
    p_debtor_kind TEXT,p_debtor UUID,p_payee_kind TEXT,p_payee UUID)
RETURNS BIGINT LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public, pg_temp AS $$
    WITH owed AS (
      SELECT coalesce(sum(CASE
        WHEN coalesce(payer.user_id,payer.contact_id)=p_payee
          AND (CASE WHEN payer.contact_id IS NULL THEN 'user' ELSE 'contact' END)=p_payee_kind
          AND coalesce(share.user_id,share.contact_id)=p_debtor
          AND (CASE WHEN share.contact_id IS NULL THEN 'user' ELSE 'contact' END)=p_debtor_kind
          THEN share.share_amount_centavos
        WHEN coalesce(payer.user_id,payer.contact_id)=p_debtor
          AND (CASE WHEN payer.contact_id IS NULL THEN 'user' ELSE 'contact' END)=p_debtor_kind
          AND coalesce(share.user_id,share.contact_id)=p_payee
          AND (CASE WHEN share.contact_id IS NULL THEN 'user' ELSE 'contact' END)=p_payee_kind
          THEN -share.share_amount_centavos ELSE 0 END),0) amount
      FROM public.transactions tx
      JOIN public.transaction_participants payer ON payer.transaction_id=tx.id AND payer.participant_role='payer'
      JOIN public.transaction_participants share ON share.transaction_id=tx.id AND share.participant_role IN ('debtor','beneficiary')
      WHERE tx.tab_id=p_tab AND tx.status NOT IN ('cancelled','disputed')
    ), paid AS (
      SELECT coalesce(sum(CASE
        WHEN coalesce(pay.payer_contact_id,pay.payer_user_id,pay.submitted_by)=p_debtor
          AND (CASE WHEN pay.payer_contact_id IS NULL THEN 'user' ELSE 'contact' END)=p_debtor_kind
          AND coalesce(pay.recipient_contact_id,pay.recipient_user_id)=p_payee
          AND (CASE WHEN pay.recipient_contact_id IS NULL THEN 'user' ELSE 'contact' END)=p_payee_kind THEN pay.amount_centavos
        WHEN coalesce(pay.payer_contact_id,pay.payer_user_id,pay.submitted_by)=p_payee
          AND (CASE WHEN pay.payer_contact_id IS NULL THEN 'user' ELSE 'contact' END)=p_payee_kind
          AND coalesce(pay.recipient_contact_id,pay.recipient_user_id)=p_debtor
          AND (CASE WHEN pay.recipient_contact_id IS NULL THEN 'user' ELSE 'contact' END)=p_debtor_kind THEN -pay.amount_centavos ELSE 0 END),0) amount
      FROM public.payments pay WHERE pay.tab_id=p_tab AND pay.status='confirmed'
    ) SELECT greatest(owed.amount-paid.amount,0)::BIGINT FROM owed,paid;
$$;
REVOKE ALL ON FUNCTION public.get_party_outstanding_internal(UUID,TEXT,UUID,TEXT,UUID) FROM PUBLIC,anon,authenticated;

-- Explicit cash records for an owner's private, unregistered-contact ledger.
-- Registered-party submissions keep recipient verification via submit_payment_v1.
CREATE FUNCTION public.record_received_payment_v1(p_operation_id UUID,p_command JSONB)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
    v_actor UUID:=auth.uid(); v_tab UUID:=(p_command->>'p_tab_id')::UUID;
    v_payer UUID:=(p_command->'payer'->>'id')::UUID;
    v_recipient UUID:=(p_command->'recipient'->>'id')::UUID;
    v_pk TEXT:=p_command->'payer'->>'kind'; v_rk TEXT:=p_command->'recipient'->>'kind';
    v_amount BIGINT:=(p_command->>'amount_centavos')::BIGINT;
    v_contact UUID; v_result UUID; v_old public.financial_operations%ROWTYPE;
BEGIN
    IF v_actor IS NULL OR NOT public.is_tab_member(v_tab,v_actor) THEN
      RAISE EXCEPTION 'Tab membership required' USING ERRCODE='42501';
    END IF;
    IF p_operation_id IS NULL OR v_pk IS NULL OR v_rk IS NULL
       OR NOT ((v_pk='contact' AND v_rk='user' AND v_recipient=v_actor)
         OR (v_pk='user' AND v_rk='contact' AND v_payer=v_actor)) THEN
      RAISE EXCEPTION 'Record requires the owner and one contact' USING ERRCODE='22023';
    END IF;
    v_contact:=CASE WHEN v_pk='contact' THEN v_payer ELSE v_recipient END;
    IF NOT EXISTS(SELECT 1 FROM public.contacts c JOIN public.tab_members tm ON tm.contact_id=c.id
      JOIN public.tabs t ON t.id=tm.tab_id WHERE c.id=v_contact AND c.owner_user_id=v_actor
      AND tm.tab_id=v_tab AND t.tab_type='individual') THEN
      RAISE EXCEPTION 'Contact must belong to this private tab' USING ERRCODE='42501';
    END IF;
    IF v_amount IS NULL OR v_amount<=0 OR p_command->>'method' IS DISTINCT FROM 'cash' THEN
      RAISE EXCEPTION 'A positive cash record is required' USING ERRCODE='22023';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtextextended(v_actor::TEXT||':'||p_operation_id::TEXT,0));
    SELECT * INTO v_old FROM public.financial_operations WHERE actor_id=v_actor AND operation_id=p_operation_id;
    IF FOUND THEN
      IF v_old.command_kind<>'contact_payment' OR v_old.command IS DISTINCT FROM p_command THEN
        RAISE EXCEPTION 'Operation ID reused with a different command' USING ERRCODE='22023';
      END IF;
      RETURN v_old.result_id;
    END IF;
    PERFORM pg_advisory_xact_lock(hashtextextended(v_tab::TEXT,0));
    IF v_amount>public.get_party_outstanding_internal(v_tab,v_pk,v_payer,v_rk,v_recipient) THEN
      RAISE EXCEPTION 'Payment exceeds outstanding balance' USING ERRCODE='22023';
    END IF;
    INSERT INTO public.payments(tab_id,submitted_by,payer_user_id,payer_contact_id,
      recipient_user_id,recipient_contact_id,amount_centavos,payment_method,note,status,confirmed_by,confirmed_at)
    VALUES(v_tab,v_actor,CASE WHEN v_pk='user' THEN v_payer END,CASE WHEN v_pk='contact' THEN v_payer END,
      CASE WHEN v_rk='user' THEN v_recipient END,CASE WHEN v_rk='contact' THEN v_recipient END,
      v_amount,'cash',p_command->>'note','confirmed',v_actor,now()) RETURNING id INTO v_result;
    INSERT INTO public.financial_operations(actor_id,operation_id,command_kind,command,result_id)
      VALUES(v_actor,p_operation_id,'contact_payment',p_command,v_result);
    RETURN v_result;
END; $$;
REVOKE ALL ON FUNCTION public.record_received_payment_v1(UUID,JSONB) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.record_received_payment_v1(UUID,JSONB) TO authenticated;

-- Extend existing internal validators to contact parties atomically.
CREATE OR REPLACE FUNCTION public.create_expense_atomic(
    p_tab_id UUID,
    p_description TEXT,
    p_category TEXT,
    p_total_amount_centavos BIGINT,
    p_paid_by_user_id UUID,
    p_participants JSONB,
    p_due_date DATE DEFAULT NULL,
    p_receipt_url TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_transaction_id UUID;
    v_participant JSONB;
    v_payer_count INTEGER := 0;
    v_share_total BIGINT := 0;
    v_user_id UUID;
    v_contact_id UUID;
    v_role TEXT;
    v_share BIGINT;
BEGIN
    IF auth.uid() IS NULL OR NOT public.is_tab_member(p_tab_id, auth.uid()) THEN
        RAISE EXCEPTION 'Not authorized to create an expense for this tab';
    END IF;
    IF p_total_amount_centavos IS NULL OR p_total_amount_centavos <= 0 THEN
        RAISE EXCEPTION 'Expense amount must be greater than zero';
    END IF;
    IF p_paid_by_user_id IS NULL
       OR (NOT public.is_tab_member(p_tab_id, p_paid_by_user_id) AND NOT EXISTS (
          SELECT 1 FROM public.contacts c JOIN public.tab_members tm ON tm.contact_id=c.id
          JOIN public.tabs t ON t.id=tm.tab_id
          WHERE c.id=p_paid_by_user_id AND c.owner_user_id=auth.uid()
            AND tm.tab_id=p_tab_id AND t.tab_type='individual')) THEN
        RAISE EXCEPTION 'Payer must be a member of the tab';
    END IF;
    IF jsonb_typeof(p_participants) <> 'array'
       OR jsonb_array_length(p_participants) = 0 THEN
        RAISE EXCEPTION 'At least one participant is required';
    END IF;

    FOR v_participant IN SELECT value FROM jsonb_array_elements(p_participants)
    LOOP
        v_user_id := NULLIF(v_participant->>'user_id', '')::UUID;
        v_contact_id := NULLIF(v_participant->>'contact_id', '')::UUID;
        v_role := COALESCE(v_participant->>'participant_role', 'debtor');
        v_share := COALESCE((v_participant->>'share_amount_centavos')::BIGINT, -1);

        IF (v_user_id IS NULL) = (v_contact_id IS NULL) THEN
            RAISE EXCEPTION 'Each participant must identify exactly one user or contact';
        END IF;
        IF v_share < 0 THEN
            RAISE EXCEPTION 'Participant share cannot be negative';
        END IF;
        IF v_role NOT IN ('payer', 'debtor', 'beneficiary') THEN
            RAISE EXCEPTION 'Invalid participant role';
        END IF;
        IF v_role = 'payer' THEN
            v_payer_count := v_payer_count + 1;
            IF COALESCE(v_user_id,v_contact_id) IS DISTINCT FROM p_paid_by_user_id THEN
                RAISE EXCEPTION 'Payer participant must match p_paid_by_user_id';
            END IF;
        END IF;
        IF v_user_id IS NOT NULL
           AND NOT public.is_tab_member(p_tab_id, v_user_id) THEN
            RAISE EXCEPTION 'User participant must be a member of the tab';
        END IF;
        IF v_contact_id IS NOT NULL
           AND NOT EXISTS (
               SELECT 1 FROM public.tab_members tm JOIN public.contacts c ON c.id=tm.contact_id
               JOIN public.tabs t ON t.id=tm.tab_id
               WHERE tm.tab_id=p_tab_id AND tm.contact_id=v_contact_id
                 AND c.owner_user_id=auth.uid() AND t.tab_type='individual'
           ) THEN
            RAISE EXCEPTION 'Contact participant must be a member of the tab';
        END IF;
        v_share_total := v_share_total + v_share;
    END LOOP;

    IF v_payer_count <> 1 THEN
        RAISE EXCEPTION 'Exactly one payer participant is required';
    END IF;
    IF v_share_total <> p_total_amount_centavos THEN
        RAISE EXCEPTION 'Participant shares must equal the total expense amount';
    END IF;

    INSERT INTO public.transactions (
        tab_id, created_by, transaction_type, category, description,
        total_amount_centavos, currency, status, due_date, receipt_url
    ) VALUES (
        p_tab_id, auth.uid(), 'shared_expense',
        COALESCE(NULLIF(trim(p_category), ''), 'other'),
        COALESCE(NULLIF(trim(p_description), ''), 'Expense'),
        p_total_amount_centavos, 'PHP', 'acknowledged',
        p_due_date, p_receipt_url
    )
    RETURNING id INTO v_transaction_id;

    INSERT INTO public.transaction_participants (
        transaction_id, user_id, contact_id, participant_role,
        share_amount_centavos, acknowledged
    )
    SELECT
        v_transaction_id,
        NULLIF(value->>'user_id', '')::UUID,
        NULLIF(value->>'contact_id', '')::UUID,
        COALESCE(value->>'participant_role', 'debtor'),
        (value->>'share_amount_centavos')::BIGINT,
        COALESCE((value->>'acknowledged')::BOOLEAN, false)
    FROM jsonb_array_elements(p_participants);

    RETURN v_transaction_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;


CREATE OR REPLACE FUNCTION public.calculate_user_tab_balance_unchecked(
    p_tab_id UUID,
    p_user_id UUID
)
RETURNS BIGINT AS $$
DECLARE
    v_owed_to_user BIGINT := 0;
    v_owed_by_user BIGINT := 0;
    v_paid_by_user BIGINT := 0;
    v_paid_to_user BIGINT := 0;
BEGIN
    SELECT COALESCE(SUM(tp.share_amount_centavos), 0)
    INTO v_owed_to_user
    FROM public.transactions t
    JOIN public.transaction_participants tp ON tp.transaction_id = t.id
    WHERE t.tab_id = p_tab_id
      AND t.status NOT IN ('cancelled', 'disputed')
      AND public.get_transaction_payer_id(t.id) = p_user_id
      AND tp.participant_role IN ('debtor', 'beneficiary')
      AND (tp.user_id IS NULL OR tp.user_id <> p_user_id);

    SELECT COALESCE(SUM(tp.share_amount_centavos), 0)
    INTO v_owed_by_user
    FROM public.transactions t
    JOIN public.transaction_participants tp ON tp.transaction_id = t.id
    WHERE t.tab_id = p_tab_id
      AND t.status NOT IN ('cancelled', 'disputed')
      AND public.get_transaction_payer_id(t.id) <> p_user_id
      AND tp.participant_role IN ('debtor', 'beneficiary')
      AND tp.user_id = p_user_id;

    SELECT COALESCE(SUM(p.amount_centavos), 0)
    INTO v_paid_by_user
    FROM public.payments p
    WHERE p.tab_id = p_tab_id
      AND p.status = 'confirmed'
      AND p.payer_contact_id IS NULL AND COALESCE(p.payer_user_id,p.submitted_by) = p_user_id;

    SELECT COALESCE(SUM(p.amount_centavos), 0)
    INTO v_paid_to_user
    FROM public.payments p
    WHERE p.tab_id = p_tab_id
      AND p.status = 'confirmed'
      AND p.recipient_contact_id IS NULL
      AND COALESCE(p.recipient_user_id,p.confirmed_by) = p_user_id;

    RETURN v_owed_to_user - v_owed_by_user
        - v_paid_to_user + v_paid_by_user;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = public, pg_temp;


CREATE OR REPLACE FUNCTION public.prevent_payment_overpayment()
RETURNS TRIGGER AS $$
DECLARE
    v_balance BIGINT;
    v_outstanding BIGINT;
BEGIN
    PERFORM pg_advisory_xact_lock(
        hashtextextended(NEW.tab_id::TEXT, 0)
    );

    IF NEW.payer_contact_id IS NOT NULL OR NEW.recipient_contact_id IS NOT NULL THEN
        v_outstanding := public.get_party_outstanding_internal(NEW.tab_id,
          CASE WHEN NEW.payer_contact_id IS NULL THEN 'user' ELSE 'contact' END,
          COALESCE(NEW.payer_contact_id,NEW.payer_user_id,NEW.submitted_by),
          CASE WHEN NEW.recipient_contact_id IS NULL THEN 'user' ELSE 'contact' END,
          COALESCE(NEW.recipient_contact_id,NEW.recipient_user_id));
        IF v_outstanding <= 0 OR NEW.amount_centavos > v_outstanding THEN
            RAISE EXCEPTION 'Payment exceeds the outstanding balance';
        END IF;
        RETURN NEW;
    END IF;
    IF NOT public.is_tab_member(NEW.tab_id, NEW.submitted_by) THEN
        RAISE EXCEPTION 'Payment submitter is not a member of this tab';
    END IF;

    -- Payments between a known pair are bounded by what that pair still owes;
    -- a tab-wide net can be smaller than a genuine bilateral debt.
    IF NEW.recipient_user_id IS NOT NULL THEN
        v_outstanding := public.get_pair_outstanding(
            NEW.tab_id,
            NEW.submitted_by,
            NEW.recipient_user_id
        );
        IF v_outstanding <= 0 OR NEW.amount_centavos > v_outstanding THEN
            RAISE EXCEPTION
                'Payment exceeds the outstanding balance between the two members';
        END IF;
        RETURN NEW;
    END IF;

    -- Legacy writers do not name a recipient, so fall back to the tab balance.
    v_balance := public.calculate_user_tab_balance_unchecked(
        NEW.tab_id,
        NEW.submitted_by
    );

    IF ABS(v_balance) < NEW.amount_centavos THEN
        RAISE EXCEPTION
            'Payment exceeds the outstanding tab balance for the submitter';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

DROP TRIGGER IF EXISTS trigger_prevent_payment_overpayment
  ON public.payments;
CREATE TRIGGER trigger_prevent_payment_overpayment
  BEFORE INSERT ON public.payments
  FOR EACH ROW EXECUTE FUNCTION public.prevent_payment_overpayment();

CREATE OR REPLACE FUNCTION public.get_net_balance(p_tab_id UUID,p_user_id UUID)
RETURNS BIGINT LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path=public,pg_temp AS $$
BEGIN
  IF auth.uid() IS NULL OR p_user_id IS DISTINCT FROM auth.uid()
     OR NOT public.is_tab_member(p_tab_id,auth.uid()) THEN
    RAISE EXCEPTION 'Not authorized to view this tab balance' USING ERRCODE='42501';
  END IF;
  RETURN public.calculate_user_tab_balance_unchecked(p_tab_id,p_user_id);
END; $$;
REVOKE ALL ON FUNCTION public.get_net_balance(UUID,UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_net_balance(UUID,UUID) TO authenticated;
