-- Add optional payment destination columns to public.users for fast profile resolution.
-- Complements public.payment_methods table.

ALTER TABLE public.users ADD COLUMN IF NOT EXISTS gcash_number TEXT;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS maya_number TEXT;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS qr_code_url TEXT;

-- Refresh PostgREST schema cache
NOTIFY pgrst, 'reload schema';
