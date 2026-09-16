# Implementation Plan: Shareable Tabby ID Friend Requests

## Scope

Implement the approved Shareable Tabby ID Friend Requests design in the Flutter client and Supabase database. Preserve the existing manual-contact friend workflow and existing auth work.

## Work sequence

1. Add red tests for `TabbyUser.friendCode`, friend-request parsing/normalization, repository RPC payload mapping, and Profile request/ID interactions.
2. Add the Supabase migration:
   - create/backfill unique server-generated `users.friend_code` values;
   - add authenticated sanitized lookup/send/list/respond RPCs;
   - restrict friendship reads and remove broad client updates in favor of the response RPC;
   - grant only authenticated execution and keep private profile fields out of response records.
3. Update the schema snapshot so it matches the migration.
4. Extend Dart configuration, models, repository, dashboard state, and providers.
5. Update Profile with the copied Tabby ID, connect-by-ID entry point, lookup/send flow, and incoming Accept/Decline cards. Refresh tabs after acceptance.
6. Run focused tests while implementing, then the full Flutter analyzer/test suite.
7. Apply the migration to the approved Supabase project and verify the functions exist without logging secrets or private user data.
8. Build and install the debug APK when a device is connected, launch it, and review the final diff for unrelated changes.

## Acceptance criteria

- A user can copy a stable-looking `TAB-XXXXXX` ID from Profile.
- Exact valid ID lookup previews only safe public profile information.
- A user can send one pending request and the target can accept or decline it.
- Accept creates/reuses the canonical bilateral tab and the friend is selectable for future debt/expense entries.
- Pending requests do not expose email, phone, payment account numbers, QR URLs, or ledger rows.
- Self requests, invalid IDs, duplicate pending requests, and unauthorized responses are rejected server-side and surfaced cleanly.
- Existing manual “Add a Friend” behavior and auth behavior remain intact.
- All tests and static checks pass.

## Risk controls

- Use server-side code generation and exact lookup; never generate codes from UUID substrings.
- Keep financial data out of friend-request responses.
- Do not merge or mutate historical ledger rows on accept.
- Treat local uncommitted auth changes as user-owned and avoid reverting them.
