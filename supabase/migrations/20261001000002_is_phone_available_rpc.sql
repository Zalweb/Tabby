-- Function to check if a phone number is available for registration
-- Normalizes non-digits and checks the last 10 digits to prevent duplicate registrations

CREATE OR REPLACE FUNCTION public.is_phone_available(p_phone TEXT, p_user_id UUID DEFAULT NULL)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_norm TEXT := regexp_replace(p_phone, '\D', '', 'g');
    v_last10 TEXT;
    v_exists BOOLEAN;
BEGIN
    IF length(v_norm) < 10 THEN
        RETURN FALSE;
    END IF;
    v_last10 := right(v_norm, 10);
    
    SELECT EXISTS (
        SELECT 1 FROM public.users
        WHERE (p_user_id IS NULL OR id != p_user_id)
          AND (
            phone = p_phone 
            OR right(regexp_replace(COALESCE(phone, ''), '\D', '', 'g'), 10) = v_last10
          )
    ) INTO v_exists;

    RETURN NOT v_exists;
END;
$$;

GRANT EXECUTE ON FUNCTION public.is_phone_available(TEXT, UUID) TO authenticated, anon;
