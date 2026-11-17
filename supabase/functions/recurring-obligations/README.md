# Recurrence worker

Rollout is disabled in both application constants and `m2_feature_flags`.
This function dispatches only the bounded service RPC. It requires the service
bearer and a separate `RECURRENCE_WORKER_SECRET`; neither belongs in client code.
No cron schedule or live deployment is established by these source files.

Rules use calendar dates in a saved IANA timezone. Each pass processes at most
25 rules, prioritizing oldest due dates; the database uniquely identifies each
rule/date and locks concurrent materialization. Failed rules need attention;
counts are processing acknowledgments, never payment confirmations. Resume
excludes previously missed dates. Confirm actual Edge runtime, secret binding,
scheduler overlap, authenticated SDK reads and device offline reconciliation in
a staging Supabase project before enabling rollout. Local Node/SQL tests do not
close these gates.
