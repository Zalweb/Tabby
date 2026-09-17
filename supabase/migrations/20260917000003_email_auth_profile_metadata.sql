-- Preserve profile details collected by email/password signup.
-- Supabase stores signup form fields in raw_user_meta_data while the email
-- provider's auth phone column remains empty.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.users (id, email, phone, display_name, avatar_url)
    VALUES (
        NEW.id,
        NEW.email,
        COALESCE(NEW.phone, NEW.raw_user_meta_data->>'phone'),
        COALESCE(
            NEW.raw_user_meta_data->>'display_name',
            NEW.raw_user_meta_data->>'name',
            split_part(COALESCE(NEW.email, 'User'), '@', 1)
        ),
        NEW.raw_user_meta_data->>'avatar_url'
    )
    ON CONFLICT (id) DO UPDATE SET
        email = COALESCE(EXCLUDED.email, public.users.email),
        phone = COALESCE(EXCLUDED.phone, public.users.phone),
        display_name = COALESCE(NULLIF(EXCLUDED.display_name, ''), public.users.display_name),
        avatar_url = COALESCE(EXCLUDED.avatar_url, public.users.avatar_url),
        updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

ALTER FUNCTION public.handle_new_user() SET search_path = public, pg_temp;
