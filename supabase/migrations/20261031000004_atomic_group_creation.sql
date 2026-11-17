-- One authenticated, retry-safe transaction creates the full group roster/tab.
CREATE TABLE public.group_creation_commands (
  actor_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  operation_id UUID NOT NULL,
  command JSONB NOT NULL,
  group_id UUID NOT NULL REFERENCES public.groups(id) ON DELETE RESTRICT,
  tab_id UUID NOT NULL REFERENCES public.tabs(id) ON DELETE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY(actor_id,operation_id)
);
ALTER TABLE public.group_creation_commands ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.group_creation_commands FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.create_group_v1(p_operation_id UUID,p_command JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_previous public.group_creation_commands%ROWTYPE;
  v_name TEXT := trim(p_command->>'name');
  v_members UUID[];
  v_group UUID;
  v_tab UUID;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE='42501';
  END IF;
  IF p_operation_id IS NULL OR p_command IS NULL OR jsonb_typeof(p_command)<>'object' THEN
    RAISE EXCEPTION 'Operation and command required' USING ERRCODE='22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('tabby-group:'||v_actor::TEXT||':'||p_operation_id::TEXT,0));
  SELECT * INTO v_previous FROM public.group_creation_commands
    WHERE actor_id=v_actor AND operation_id=p_operation_id;
  IF FOUND THEN
    IF v_previous.command IS DISTINCT FROM p_command THEN
      RAISE EXCEPTION 'Operation reused with different group details' USING ERRCODE='22023';
    END IF;
    RETURN jsonb_build_object('group_id',v_previous.group_id,'tab_id',v_previous.tab_id);
  END IF;
  IF v_name IS NULL OR length(v_name)<1 OR length(v_name)>80
     OR jsonb_typeof(p_command->'member_user_ids') IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'Group name and member list required' USING ERRCODE='22023';
  END IF;
  SELECT array_agg(value::UUID) INTO v_members
    FROM jsonb_array_elements_text(p_command->'member_user_ids');
  IF COALESCE(cardinality(v_members),0)<1 OR cardinality(v_members)>99
     OR v_actor=ANY(v_members) OR array_position(v_members,NULL) IS NOT NULL
     OR cardinality(v_members)<>(SELECT count(DISTINCT id) FROM unnest(v_members) id) THEN
    RAISE EXCEPTION 'Choose distinct registered friends' USING ERRCODE='22023';
  END IF;
  IF EXISTS (SELECT 1 FROM unnest(v_members) member_id WHERE NOT EXISTS (
    SELECT 1 FROM public.friendships f WHERE f.status='accepted' AND
      ((f.requester_id=v_actor AND f.addressee_id=member_id) OR
       (f.addressee_id=v_actor AND f.requester_id=member_id)))) THEN
    RAISE EXCEPTION 'Every group member must be an accepted friend' USING ERRCODE='42501';
  END IF;
  INSERT INTO public.groups(created_by,name) VALUES(v_actor,v_name) RETURNING id INTO v_group;
  INSERT INTO public.group_members(group_id,user_id,role,status)
    VALUES(v_group,v_actor,'admin','active');
  INSERT INTO public.group_members(group_id,user_id,role,status)
    SELECT v_group,id,'member','active' FROM unnest(v_members) id;
  INSERT INTO public.tabs(tab_type,group_id,status) VALUES('group',v_group,'active') RETURNING id INTO v_tab;
  INSERT INTO public.tab_members(tab_id,user_id,role) VALUES(v_tab,v_actor,'admin');
  INSERT INTO public.tab_members(tab_id,user_id,role)
    SELECT v_tab,id,'participant' FROM unnest(v_members) id;
  INSERT INTO public.group_creation_commands(actor_id,operation_id,command,group_id,tab_id)
    VALUES(v_actor,p_operation_id,p_command,v_group,v_tab);
  RETURN jsonb_build_object('group_id',v_group,'tab_id',v_tab);
END; $$;
REVOKE ALL ON FUNCTION public.create_group_v1(UUID,JSONB) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_group_v1(UUID,JSONB) TO authenticated;
-- Legacy multi-request creation cannot leave partially committed rosters.
REVOKE INSERT ON public.groups,public.group_members,public.tabs,public.tab_members
  FROM PUBLIC,anon,authenticated;
