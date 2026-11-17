-- Normalize malformed JSON-backed financial input at the PostgREST boundary.
-- PT400 is the existing project convention for a stable HTTP 400 response.
CREATE FUNCTION public.raise_financial_input_validation_v1() RETURNS void
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
BEGIN
  RAISE SQLSTATE 'PT400' USING MESSAGE='Invalid financial input. Enter amounts as whole centavos and check the submitted values.';
END $$;
REVOKE ALL ON FUNCTION public.raise_financial_input_validation_v1() FROM PUBLIC,anon,authenticated;

-- Keep the public RPC signatures stable while catching PostgreSQL text-to-number
-- and range errors raised by nested validators. Raw SQLSTATE/details never cross
-- the client boundary. The unchecked implementations remain private helpers.
ALTER FUNCTION public.create_expense_v1(uuid,jsonb) RENAME TO create_expense_v1_unmapped;
REVOKE ALL ON FUNCTION public.create_expense_v1_unmapped(uuid,jsonb) FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.create_expense_v1(p_operation_id uuid,p_command jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  RETURN public.create_expense_v1_unmapped(p_operation_id,p_command);
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
  PERFORM public.raise_financial_input_validation_v1();
END $$;
GRANT EXECUTE ON FUNCTION public.create_expense_v1(uuid,jsonb) TO authenticated;

ALTER FUNCTION public.submit_payment_v1(uuid,jsonb) RENAME TO submit_payment_v1_unmapped;
REVOKE ALL ON FUNCTION public.submit_payment_v1_unmapped(uuid,jsonb) FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.submit_payment_v1(p_operation_id uuid,p_command jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  RETURN public.submit_payment_v1_unmapped(p_operation_id,p_command);
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
  PERFORM public.raise_financial_input_validation_v1();
END $$;
GRANT EXECUTE ON FUNCTION public.submit_payment_v1(uuid,jsonb) TO authenticated;

ALTER FUNCTION public.record_received_payment_v1(uuid,jsonb) RENAME TO record_received_payment_v1_unmapped;
REVOKE ALL ON FUNCTION public.record_received_payment_v1_unmapped(uuid,jsonb) FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.record_received_payment_v1(p_operation_id uuid,p_command jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  RETURN public.record_received_payment_v1_unmapped(p_operation_id,p_command);
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
  PERFORM public.raise_financial_input_validation_v1();
END $$;
GRANT EXECUTE ON FUNCTION public.record_received_payment_v1(uuid,jsonb) TO authenticated;

ALTER FUNCTION public.submit_payment_v2(uuid,jsonb) RENAME TO submit_payment_v2_unmapped;
REVOKE ALL ON FUNCTION public.submit_payment_v2_unmapped(uuid,jsonb) FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.submit_payment_v2(p_operation_id uuid,p_command jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  RETURN public.submit_payment_v2_unmapped(p_operation_id,p_command);
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
  PERFORM public.raise_financial_input_validation_v1();
END $$;
GRANT EXECUTE ON FUNCTION public.submit_payment_v2(uuid,jsonb) TO authenticated;

-- These M2 RPCs remain disabled by their feature flags. Their error boundary is
-- still normalized so enabling a feature cannot expose raw numeric parser errors.
ALTER FUNCTION public.create_expense_v3(uuid,jsonb) RENAME TO create_expense_v3_unmapped;
REVOKE ALL ON FUNCTION public.create_expense_v3_unmapped(uuid,jsonb) FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.create_expense_v3(p_operation_id uuid,p_command jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  RETURN public.create_expense_v3_unmapped(p_operation_id,p_command);
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
  PERFORM public.raise_financial_input_validation_v1();
END $$;
GRANT EXECUTE ON FUNCTION public.create_expense_v3(uuid,jsonb) TO authenticated;

ALTER FUNCTION public.change_recurrence_v1(uuid,jsonb) RENAME TO change_recurrence_v1_unmapped;
REVOKE ALL ON FUNCTION public.change_recurrence_v1_unmapped(uuid,jsonb) FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.change_recurrence_v1(p_operation_id uuid,p_command jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  RETURN public.change_recurrence_v1_unmapped(p_operation_id,p_command);
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
  PERFORM public.raise_financial_input_validation_v1();
END $$;
GRANT EXECUTE ON FUNCTION public.change_recurrence_v1(uuid,jsonb) TO authenticated;

ALTER FUNCTION public.materialize_recurrence_v1(uuid,jsonb) RENAME TO materialize_recurrence_v1_unmapped;
REVOKE ALL ON FUNCTION public.materialize_recurrence_v1_unmapped(uuid,jsonb) FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.materialize_recurrence_v1(p_operation_id uuid,p_command jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  RETURN public.materialize_recurrence_v1_unmapped(p_operation_id,p_command);
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
  PERFORM public.raise_financial_input_validation_v1();
END $$;
GRANT EXECUTE ON FUNCTION public.materialize_recurrence_v1(uuid,jsonb) TO authenticated;

ALTER FUNCTION public.review_expense_v1(uuid,jsonb) RENAME TO review_expense_v1_unmapped;
REVOKE ALL ON FUNCTION public.review_expense_v1_unmapped(uuid,jsonb) FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.review_expense_v1(p_operation_id uuid,p_command jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  RETURN public.review_expense_v1_unmapped(p_operation_id,p_command);
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
  PERFORM public.raise_financial_input_validation_v1();
END $$;
GRANT EXECUTE ON FUNCTION public.review_expense_v1(uuid,jsonb) TO authenticated;
