-- New/changed rows must fit the agreed PHP input range. NOT VALID preserves
-- historical rows for explicit review instead of rewriting financial history.
ALTER TABLE public.transactions ADD CONSTRAINT transaction_m1_amount_limit
  CHECK(total_amount_centavos<=99999999999) NOT VALID;
ALTER TABLE public.transaction_participants ADD CONSTRAINT participant_m1_amount_limit
  CHECK(share_amount_centavos<=99999999999) NOT VALID;
ALTER TABLE public.payments ADD CONSTRAINT payment_m1_amount_limit
  CHECK(amount_centavos<=99999999999) NOT VALID;
