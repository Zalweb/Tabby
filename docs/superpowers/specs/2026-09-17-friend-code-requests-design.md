# Shareable Tabby ID Friend Requests

## Status

Approved for implementation on 2026-09-17.

## Goal

Let authenticated Tabby users connect with one another using a safe, shareable identifier instead of exposing or asking users to exchange Supabase UUIDs. A successful connection must feed the existing one-tab-per-relationship ledger so future expenses, payments, and reminders stay in one canonical bilateral tab.

## User experience

1. Every registered user receives a human-shareable Tabby ID such as `TAB-7K4P2M`.
2. The owner can see and copy their own Tabby ID from Profile.
3. Add Friend offers a “Connect by Tabby ID” path. Search is exact after normalizing case, whitespace, and an optional `TAB-` prefix.
4. A matching user is previewed with display name and avatar only. The requester sends a pending request.
5. The addressee sees incoming requests in Profile and can Accept or Decline.
6. Accepting the request creates or reuses the canonical active bilateral tab. The new friend then appears in the existing Friends list and can be selected by Add Expense.
7. Declining leaves no connection or ledger access. A requester may send a new request later according to the server’s relationship rules.

The existing manual contact form remains available for people who do not have an account yet. It must not silently merge an old contact tab into a registered-user tab by matching names. A separate, explicit merge/link flow can be added later.

## Data and security design

### User identifier

Add `public.users.friend_code TEXT NOT NULL UNIQUE`. Codes are generated server-side from an uppercase, unambiguous alphabet and are not derived from the UUID. Existing rows receive a backfilled code. The code is safe to share, but it is still treated as a lookup credential: exact lookup returns only public profile fields.

### RPC contract

- `find_user_by_friend_code(p_friend_code TEXT)` returns at most one sanitized profile and the current relationship state. It requires an authenticated caller, rejects blank/invalid input, and never returns email, phone, GCash, Maya, QR, or UUID in the client-facing UI.
- `send_friend_request(p_friend_code TEXT)` authenticates the caller, rejects self-requests, resolves the code, handles an existing accepted/pending relationship, and creates a pending friendship. It returns the request and sanitized addressee profile.
- `list_friend_requests()` returns only requests involving the authenticated user, with sanitized requester/addressee profiles and no private payment fields.
- `respond_friend_request(p_friendship_id UUID, p_accept BOOLEAN)` permits only the addressee to respond. Decline records the response. Accept records the response and calls the existing authorization-hardened `get_or_create_bilateral_tab` for the two parties, returning the canonical tab ID.

All RPCs are authenticated-only, use a fixed `search_path`, and validate `auth.uid()` server-side. Client-provided UUIDs are never used to identify a friend in the UI; the response RPC receives a request ID only after it was loaded from the caller’s own request list.

### RLS

Friendship rows are readable only by their requester or addressee. Generic updates are not used for accepting or declining; the response RPC owns the state transition and verifies the addressee. Pending relationships do not grant access to private user fields or tabs. Existing accepted-friend/tab membership policies remain the source of truth for ledger data.

## Client architecture

- Extend `TabbyUser` with an optional `friendCode`.
- Add a `FriendRequest` model with request ID, requester/addressee, status, timestamps, and an `isIncoming` convenience property.
- Add repository methods for lookup, send, list, and respond; keep response mapping defensive for PostgREST JSON values.
- Add friend requests to dashboard state and load them alongside tabs. Accept refreshes tabs so the canonical ledger is immediately visible.
- Profile gains the current user’s Tabby ID card, copy action, Connect by Tabby ID form, and incoming request cards.
- Errors are shown as warm, actionable messages. No red debt-collection language or emojis are introduced.

## Debt connection behavior

Once accepted, the relationship’s existing bilateral tab is the destination for future entries. No financial rows are copied or rewritten as part of accepting a request. This preserves append-only auditability and avoids accidental merges between an existing unregistered contact and a registered account.

## Non-goals

- Contact discovery, fuzzy name search, phone-number search, or exposing raw UUIDs.
- Automatic migration of old contact tabs.
- Blocking, removing, or muting friends beyond the existing friendship status model.
- Sending push notifications or external messages; the first version refreshes requests on Profile load and after user actions.

## Verification

Test model normalization and request mapping, Profile rendering and interaction states, repository RPC payloads, and SQL security invariants. Run `flutter analyze`, `flutter test`, `git diff --check`, a debug APK build, and (when the tablet is available) install/launch verification. Apply and smoke-test the Supabase migration against the approved project.
