BEGIN;
CREATE TABLE public.contact_claim_invitations(
 id uuid PRIMARY KEY,owner_id uuid NOT NULL REFERENCES public.users(id),target_id uuid NOT NULL REFERENCES public.users(id),
 contact_id uuid NOT NULL REFERENCES public.contacts(id),source_tab_id uuid NOT NULL REFERENCES public.tabs(id),
 snapshot jsonb NOT NULL,status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','declined','accepted','superseded')),
 destination_tab_id uuid REFERENCES public.tabs(id),reverse_id uuid REFERENCES public.transactions(id),transfer_id uuid REFERENCES public.transactions(id),
 created_at timestamptz NOT NULL DEFAULT now(),decided_at timestamptz,CHECK(owner_id<>target_id));
CREATE UNIQUE INDEX ON public.contact_claim_invitations(contact_id) WHERE status='pending';
ALTER TABLE public.contact_claim_invitations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.contact_claim_invitations FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.claim_contact(uuid,uuid) FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.claim_source_snapshot_v1(p_contact uuid,p_owner uuid,p_tab uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE financial jsonb;n bigint;count_rows integer;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.contacts WHERE id=p_contact AND owner_user_id=p_owner AND claimed_user_id IS NULL AND claim_status='unclaimed') OR
   NOT EXISTS(SELECT 1 FROM public.tabs WHERE id=p_tab AND user_a=p_owner AND user_b IS NULL AND tab_type='individual' AND status='active') OR
   (SELECT count(*) FROM public.tab_members WHERE contact_id=p_contact)<>1 OR
   NOT EXISTS(SELECT 1 FROM public.tab_members WHERE tab_id=p_tab AND contact_id=p_contact) OR
   EXISTS(SELECT 1 FROM public.tab_members WHERE tab_id=p_tab AND (user_id IS DISTINCT FROM p_owner AND contact_id IS DISTINCT FROM p_contact)) THEN
   RAISE EXCEPTION 'Ambiguous or unavailable contact relationship' USING ERRCODE='22023'; END IF;
 IF EXISTS(SELECT 1 FROM public.payments WHERE tab_id=p_tab AND status='submitted') OR
    EXISTS(SELECT 1 FROM public.expense_change_requests r JOIN public.transactions t ON t.id=r.transaction_id WHERE t.tab_id=p_tab AND NOT EXISTS(SELECT 1 FROM public.expense_change_results WHERE change_id=r.id) AND NOT EXISTS(SELECT 1 FROM public.expense_change_decisions WHERE change_id=r.id AND NOT accepted)) THEN
   RAISE EXCEPTION 'Resolve pending financial decisions first' USING ERRCODE='22023'; END IF;
 SELECT count(*) INTO count_rows FROM public.transactions WHERE tab_id=p_tab;
 IF count_rows>5000 THEN RAISE EXCEPTION 'Contact history requires reconciliation' USING ERRCODE='22023'; END IF;
 SELECT jsonb_build_object('expenses',coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.id) FROM public.transactions t WHERE tab_id=p_tab),'[]'),
 'shares',coalesce((SELECT jsonb_agg(to_jsonb(s) ORDER BY s.id) FROM public.transaction_participants s JOIN public.transactions t ON t.id=s.transaction_id WHERE t.tab_id=p_tab),'[]'),
 'payments',coalesce((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.id) FROM public.payments p WHERE tab_id=p_tab),'[]')) INTO financial;
 n:=public.get_party_outstanding_internal(p_tab,'contact',p_contact,'user',p_owner)-public.get_party_outstanding_internal(p_tab,'user',p_owner,'contact',p_contact);
 IF abs(n)>99999999999 THEN RAISE EXCEPTION 'Net balance requires explicit reconciliation' USING ERRCODE='22023';END IF;
 RETURN jsonb_build_object('digest',md5(financial::text),'owner_net_centavos',n,'expense_count',count_rows);
END $$;
REVOKE ALL ON FUNCTION public.claim_source_snapshot_v1(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.invite_contact_claim_v1(p_operation_id uuid,p_command jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE result uuid;c public.contacts;snapshot jsonb;target uuid:=(p_command->>'target_id')::uuid;tab uuid:=(p_command->>'source_tab_id')::uuid;
BEGIN
 result:=public.require_m2_v1('contact_claiming',p_operation_id,p_command,'m2_claim_invite');IF result IS NOT NULL THEN RETURN result;END IF;
 IF p_command-ARRAY['p_expected_actor','claim_id','contact_id','target_id','source_tab_id','snapshot_digest']<>'{}' THEN RAISE EXCEPTION 'Unsupported claim fields' USING ERRCODE='22023';END IF;
 LOCK TABLE public.transactions,public.transaction_participants,public.payments IN SHARE ROW EXCLUSIVE MODE;
 SELECT * INTO c FROM public.contacts WHERE id=(p_command->>'contact_id')::uuid FOR UPDATE;
 IF EXISTS(SELECT 1 FROM public.friendships WHERE status='blocked' AND least(requester_id,addressee_id)=least(auth.uid(),target) AND greatest(requester_id,addressee_id)=greatest(auth.uid(),target)) THEN RAISE EXCEPTION 'Relationship unavailable' USING ERRCODE='42501';END IF;
 IF c.owner_user_id IS DISTINCT FROM auth.uid() OR target=auth.uid() OR NOT EXISTS(SELECT 1 FROM public.users WHERE id=target AND anonymized_at IS NULL) THEN RAISE EXCEPTION 'Claim not authorized' USING ERRCODE='42501';END IF;
 snapshot:=public.claim_source_snapshot_v1(c.id,auth.uid(),tab);
 IF snapshot->>'digest' IS DISTINCT FROM p_command->>'snapshot_digest' THEN RAISE EXCEPTION 'Refresh contact history before inviting' USING ERRCODE='40001';END IF;
 UPDATE public.contact_claim_invitations SET status='superseded',decided_at=now() WHERE contact_id=c.id AND status='pending';
 INSERT INTO public.contact_claim_invitations(id,owner_id,target_id,contact_id,source_tab_id,snapshot)
 VALUES((p_command->>'claim_id')::uuid,auth.uid(),target,c.id,tab,snapshot) RETURNING id INTO result;
 RETURN public.record_m2_v1(p_operation_id,'m2_claim_invite',p_command,result);
END $$;
CREATE FUNCTION public.decide_contact_claim_v1(p_operation_id uuid,p_command jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE result uuid;c public.contact_claim_invitations;snapshot jsonb;net bigint;dest uuid;v_reverse uuid;v_transfer uuid;parts jsonb;
BEGIN
 result:=public.require_m2_v1('contact_claiming',p_operation_id,p_command,'m2_claim_decide');IF result IS NOT NULL THEN RETURN result;END IF;
 IF p_command-ARRAY['p_expected_actor','claim_id','accept','snapshot_digest']<>'{}' OR jsonb_typeof(p_command->'accept') IS DISTINCT FROM 'boolean' THEN RAISE EXCEPTION 'Explicit decision required' USING ERRCODE='22023';END IF;
 -- Same order as invitation and before any claim/contact rows. Legacy financial
 -- writers do not take claim locks: these short table locks freeze their DML.
 LOCK TABLE public.transactions,public.transaction_participants,public.payments IN SHARE ROW EXCLUSIVE MODE;
 SELECT * INTO c FROM public.contact_claim_invitations WHERE id=(p_command->>'claim_id')::uuid FOR UPDATE;
 IF c.id IS NULL OR c.target_id<>auth.uid() THEN RAISE EXCEPTION 'Only the invited account can decide' USING ERRCODE='42501';END IF;
 IF c.status IN ('accepted','declined') THEN
  IF (c.status='accepted') IS DISTINCT FROM (p_command->>'accept')::boolean OR c.snapshot->>'digest' IS DISTINCT FROM p_command->>'snapshot_digest' THEN RAISE EXCEPTION 'Decision conflict' USING ERRCODE='22023';END IF;
  RETURN public.record_m2_v1(p_operation_id,'m2_claim_decide',p_command,c.id);
 END IF;
 IF c.status<>'pending' OR c.snapshot->>'digest' IS DISTINCT FROM p_command->>'snapshot_digest' THEN RAISE EXCEPTION 'Invitation is stale' USING ERRCODE='40001';END IF;
 IF NOT (p_command->>'accept')::boolean THEN
  UPDATE public.contact_claim_invitations SET status='declined',decided_at=now() WHERE id=c.id;
  RETURN public.record_m2_v1(p_operation_id,'m2_claim_decide',p_command,c.id);
 END IF;
 PERFORM 1 FROM public.contacts WHERE id=c.contact_id FOR UPDATE;
 snapshot:=public.claim_source_snapshot_v1(c.contact_id,c.owner_id,c.source_tab_id);
 IF snapshot IS DISTINCT FROM c.snapshot THEN RAISE EXCEPTION 'History changed; request a fresh invitation' USING ERRCODE='40001';END IF;
 IF EXISTS(SELECT 1 FROM public.users WHERE id IN (c.owner_id,c.target_id) AND anonymized_at IS NOT NULL) THEN RAISE EXCEPTION 'Account inactive' USING ERRCODE='42501';END IF;
 net:=(snapshot->>'owner_net_centavos')::bigint;
 INSERT INTO public.tabs(user_a,user_b) VALUES(least(c.owner_id,c.target_id),greatest(c.owner_id,c.target_id)) ON CONFLICT DO NOTHING;
 SELECT id INTO STRICT dest FROM public.tabs WHERE tab_type='individual' AND status='active' AND least(user_a,user_b)=least(c.owner_id,c.target_id) AND greatest(user_a,user_b)=greatest(c.owner_id,c.target_id);
 INSERT INTO public.tab_members(tab_id,user_id) VALUES(dest,c.owner_id),(dest,c.target_id) ON CONFLICT DO NOTHING;
 IF net<>0 THEN
  parts:=jsonb_build_array(jsonb_build_object('user_id',c.owner_id,'participant_role',CASE WHEN net>0 THEN 'debtor' ELSE 'payer' END,'share_amount_centavos',CASE WHEN net>0 THEN abs(net) ELSE 0 END,'acknowledged',false),
   jsonb_build_object('contact_id',c.contact_id,'participant_role',CASE WHEN net>0 THEN 'payer' ELSE 'debtor' END,'share_amount_centavos',CASE WHEN net>0 THEN 0 ELSE abs(net) END,'acknowledged',false));
  v_reverse:=public.create_rule_expense_internal_v1(c.owner_id,c.source_tab_id,'Contact claim offset '||c.id,'other',abs(net),CASE WHEN net>0 THEN c.contact_id ELSE c.owner_id END,parts,NULL,NULL);
  parts:=jsonb_build_array(jsonb_build_object('user_id',c.owner_id,'participant_role',CASE WHEN net>0 THEN 'payer' ELSE 'debtor' END,'share_amount_centavos',CASE WHEN net>0 THEN 0 ELSE abs(net) END,'acknowledged',false),
   jsonb_build_object('user_id',c.target_id,'participant_role',CASE WHEN net>0 THEN 'debtor' ELSE 'payer' END,'share_amount_centavos',CASE WHEN net>0 THEN abs(net) ELSE 0 END,'acknowledged',false));
  v_transfer:=public.create_rule_expense_internal_v1(c.owner_id,dest,'Accepted contact claim '||c.id,'other',abs(net),CASE WHEN net>0 THEN c.owner_id ELSE c.target_id END,parts,NULL,NULL);
 END IF;
 UPDATE public.contact_claim_invitations SET status='accepted',destination_tab_id=dest,reverse_id=v_reverse,transfer_id=v_transfer,decided_at=now() WHERE id=c.id;
 UPDATE public.contacts SET claimed_user_id=c.target_id,claim_status='claimed',claimed_at=now() WHERE id=c.contact_id;
 UPDATE public.tabs SET status='archived' WHERE id=c.source_tab_id;
 RETURN public.record_m2_v1(p_operation_id,'m2_claim_decide',p_command,c.id);
END $$;
CREATE FUNCTION public.guard_contact_claim_identity_v1() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
 IF TG_OP='INSERT' THEN
 IF NEW.claimed_user_id IS NOT NULL OR NEW.claim_status<>'unclaimed' OR NEW.claimed_at IS NOT NULL THEN RAISE EXCEPTION 'New contacts must be unclaimed' USING ERRCODE='42501';END IF;RETURN NEW;END IF;
 IF NEW.owner_user_id IS DISTINCT FROM OLD.owner_user_id THEN RAISE EXCEPTION 'Contact owner is immutable' USING ERRCODE='42501';END IF;
 IF (NEW.claimed_user_id,NEW.claim_status,NEW.claimed_at) IS DISTINCT FROM (OLD.claimed_user_id,OLD.claim_status,OLD.claimed_at) AND
 NOT EXISTS(SELECT 1 FROM public.contact_claim_invitations WHERE contact_id=NEW.id AND status='accepted' AND target_id=NEW.claimed_user_id AND NEW.claim_status='claimed' AND OLD.claimed_user_id IS NULL) THEN
 RAISE EXCEPTION 'Use explicit consent flow' USING ERRCODE='42501';END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER protect_contact_claim BEFORE INSERT OR UPDATE ON public.contacts FOR EACH ROW EXECUTE FUNCTION public.guard_contact_claim_identity_v1();
CREATE FUNCTION public.guard_claimed_source_v1() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM public.contact_claim_invitations WHERE source_tab_id=NEW.tab_id AND status='accepted') THEN RAISE EXCEPTION 'Claimed source history is closed' USING ERRCODE='42501';END IF;RETURN NEW;
END $$;
CREATE TRIGGER closed_claim_transactions BEFORE INSERT ON public.transactions FOR EACH ROW EXECUTE FUNCTION public.guard_claimed_source_v1();
CREATE TRIGGER closed_claim_payments BEFORE INSERT ON public.payments FOR EACH ROW EXECUTE FUNCTION public.guard_claimed_source_v1();
-- Retained contact participants are never rewritten to a registered UUID.
CREATE OR REPLACE FUNCTION public.is_tab_member(p_tab_id uuid,p_user_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
 SELECT public.account_is_active_v1() AND p_user_id IS NOT NULL AND (
 EXISTS(SELECT 1 FROM public.tab_members WHERE tab_id=p_tab_id AND user_id=p_user_id) OR
 EXISTS(SELECT 1 FROM public.tabs WHERE id=p_tab_id AND (user_a=p_user_id OR user_b=p_user_id)) OR
 EXISTS(SELECT 1 FROM public.tabs t JOIN public.group_members gm ON gm.group_id=t.group_id WHERE t.id=p_tab_id AND gm.user_id=p_user_id AND gm.status='active') OR
 EXISTS(SELECT 1 FROM public.contact_claim_invitations WHERE source_tab_id=p_tab_id AND target_id=p_user_id AND status='accepted'));
$$;
CREATE FUNCTION public.find_claim_target_v1(p_friend_code text) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE target jsonb;
BEGIN
 PERFORM public.tabby_pre_request();IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='42501';END IF;
 -- Reuse existing anti-enumeration/blocklist and exact friend-code lookup.
 SELECT jsonb_build_object('id',id,'display_name',display_name,'friend_code',friend_code) INTO target FROM public.find_user_by_friend_code(p_friend_code);
 RETURN jsonb_build_object('account_id',auth.uid(),'target',target);
END $$;
CREATE FUNCTION public.contact_claim_preview_v1(p_contact_id uuid,p_source_tab_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
 PERFORM public.tabby_pre_request();IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='42501';END IF;
 RETURN jsonb_build_object('account_id',auth.uid(),'contact_id',p_contact_id,'source_tab_id',p_source_tab_id,'snapshot',public.claim_source_snapshot_v1(p_contact_id,auth.uid(),p_source_tab_id));
END $$;
CREATE FUNCTION public.list_contact_claims_v1(p_after uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE records jsonb;last_id uuid;more boolean;
BEGIN
 PERFORM public.tabby_pre_request();IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='42501';END IF;
 WITH window_rows AS (SELECT * FROM public.contact_claim_invitations WHERE (owner_id=auth.uid() OR target_id=auth.uid()) AND (p_after IS NULL OR id>p_after) ORDER BY id LIMIT 51),page AS (SELECT * FROM window_rows ORDER BY id LIMIT 50)
 SELECT coalesce(jsonb_agg(to_jsonb(p) ORDER BY id),'[]'),(SELECT id FROM page ORDER BY id DESC LIMIT 1),(SELECT count(*)>50 FROM window_rows) INTO records,last_id,more FROM page p;
 RETURN jsonb_build_object('account_id',auth.uid(),'records',records,'next_cursor',CASE WHEN more THEN last_id ELSE NULL END);
END $$;
CREATE FUNCTION public.contact_claim_history_page_v1(p_claim_id uuid,p_after uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE c public.contact_claim_invitations;records jsonb;last_id uuid;more boolean;
BEGIN
 PERFORM public.tabby_pre_request();SELECT * INTO c FROM public.contact_claim_invitations WHERE id=p_claim_id;
 IF auth.uid() IS NULL OR c.id IS NULL OR NOT(auth.uid()=c.owner_id OR (auth.uid()=c.target_id AND c.status IN ('pending','accepted'))) THEN RAISE EXCEPTION 'History not authorized' USING ERRCODE='42501';END IF;
 WITH window_rows AS (SELECT t.id,t.description,t.total_amount_centavos,t.created_at,t.status,
 (SELECT jsonb_agg(jsonb_build_object('party',jsonb_build_object('kind',CASE WHEN s.contact_id IS NULL THEN 'user' ELSE 'contact' END,'id',coalesce(s.user_id,s.contact_id)),'role',s.participant_role,'share_centavos',s.share_amount_centavos) ORDER BY s.id) FROM public.transaction_participants s WHERE s.transaction_id=t.id) participants
 FROM public.transactions t WHERE t.tab_id=c.source_tab_id AND (p_after IS NULL OR t.id>p_after) ORDER BY t.id LIMIT 51),page AS(SELECT * FROM window_rows ORDER BY id LIMIT 50)
 SELECT coalesce(jsonb_agg(to_jsonb(p) ORDER BY id),'[]'),(SELECT id FROM page ORDER BY id DESC LIMIT 1),(SELECT count(*)>50 FROM window_rows) INTO records,last_id,more FROM page p;
 RETURN jsonb_build_object('account_id',auth.uid(),'claim_id',c.id,'records',records,'next_cursor',CASE WHEN more THEN last_id ELSE NULL END);
END $$;
REVOKE ALL ON FUNCTION public.invite_contact_claim_v1(uuid,jsonb),public.decide_contact_claim_v1(uuid,jsonb),public.find_claim_target_v1(text),public.contact_claim_preview_v1(uuid,uuid),public.list_contact_claims_v1(uuid),public.contact_claim_history_page_v1(uuid,uuid),public.guard_contact_claim_identity_v1(),public.guard_claimed_source_v1() FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.guard_contact_claim_identity_v1(),public.guard_claimed_source_v1() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.invite_contact_claim_v1(uuid,jsonb),public.decide_contact_claim_v1(uuid,jsonb),public.find_claim_target_v1(text),public.contact_claim_preview_v1(uuid,uuid),public.list_contact_claims_v1(uuid),public.contact_claim_history_page_v1(uuid,uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.protect_shared_archive_v1() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
 IF NEW.status IS DISTINCT FROM OLD.status AND (NEW.status='archived' OR OLD.status='archived') AND current_setting('role',true) IN ('anon','authenticated') AND
 NOT (OLD.status='active' AND NEW.status='archived' AND EXISTS(SELECT 1 FROM public.contact_claim_invitations WHERE source_tab_id=NEW.id AND status='accepted')) THEN
 RAISE EXCEPTION 'Use private Connections archive' USING ERRCODE='42501';END IF;RETURN NEW;
END $$;
CREATE FUNCTION public.contact_claim_payments_page_v1(p_claim_id uuid,p_after uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE c public.contact_claim_invitations;records jsonb;last_id uuid;more boolean;
BEGIN
 PERFORM public.tabby_pre_request();SELECT * INTO c FROM public.contact_claim_invitations WHERE id=p_claim_id;
 IF auth.uid() IS NULL OR c.id IS NULL OR NOT(auth.uid()=c.owner_id OR (auth.uid()=c.target_id AND c.status IN ('pending','accepted'))) THEN RAISE EXCEPTION 'History not authorized' USING ERRCODE='42501';END IF;
 WITH window_rows AS (SELECT id,amount_centavos,status,created_at,payer_user_id,payer_contact_id,recipient_user_id,recipient_contact_id FROM public.payments WHERE tab_id=c.source_tab_id AND (p_after IS NULL OR id>p_after) ORDER BY id LIMIT 51),page AS(SELECT * FROM window_rows ORDER BY id LIMIT 50)
 SELECT coalesce(jsonb_agg(to_jsonb(p) ORDER BY id),'[]'),(SELECT id FROM page ORDER BY id DESC LIMIT 1),(SELECT count(*)>50 FROM window_rows) INTO records,last_id,more FROM page p;
 RETURN jsonb_build_object('account_id',auth.uid(),'claim_id',c.id,'records',records,'next_cursor',CASE WHEN more THEN last_id ELSE NULL END);
END $$;
REVOKE ALL ON FUNCTION public.contact_claim_payments_page_v1(uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.contact_claim_payments_page_v1(uuid,uuid) TO authenticated;

CREATE FUNCTION public.guard_claimed_participants_v1() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM public.transactions t JOIN public.contact_claim_invitations c ON c.source_tab_id=t.tab_id WHERE t.id=NEW.transaction_id AND c.status='accepted') THEN RAISE EXCEPTION 'Claimed source history is closed' USING ERRCODE='42501';END IF;RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.guard_claimed_participants_v1() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER closed_claim_participants BEFORE INSERT ON public.transaction_participants FOR EACH ROW EXECUTE FUNCTION public.guard_claimed_participants_v1();
COMMIT;