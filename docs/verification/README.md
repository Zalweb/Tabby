# Verification records

Use the [template](../templates/verification-record.md). Name records with stable IDs and link them in task metadata. Record exact tested commit, dirty-tree state, timestamp, agent/platform, tool versions, device/API or database version/migrations, command/scenario, expected/actual outcome and sanitized evidence. Include failed and unrun checks.

Evidence types: static review, unit/widget, backend integration, Android device, release artifact and documentation tooling. Required checks in task metadata name the acceptance categories. Each verified/complete task must link passed evidence for every required category; integration checks cannot be satisfied by mocks. Mark unavailable device/backend checks unverified with a next action.

Do not commit tokens, real account data, proof images or machine-specific file links. Use durable CI URLs or relative sanitized artifacts. A source migration is not deployed evidence. A passing build is not signed-artifact or release evidence. Test counts apply only to their recorded revision and environment.

For local money-command SQL checks, install the optional harness in ignored tooling storage with `npm install --prefix .dart_tool/sql-check --no-save @electric-sql/pglite@0.5.14`, then run `node scripts/test-money-commands.cjs`. It executes the real financial table/validator/RPC migration subset in PostgreSQL/WASM with an injected JWT-subject function. It excludes native extension provisioning and unrelated Supabase migrations/services. PGlite serializes parallel calls: this is local contract evidence, not full fresh-install, staging, network response-loss or independent-session concurrency acceptance.

For native financial-contract and independent-session checks, install optional tooling using `npm install --prefix .dart_tool/native-db --no-save embedded-postgres@17.11.0-beta.19`, then run `node scripts/test-backend-native.cjs`. It starts a unique synthetic PostgreSQL 17.11 cluster on loopback, applies the financial migration subset with native extensions, exercises eight distinct DB sessions, stops the server and retains ignored fixture files. It creates no host users and uses generated test credentials. It is not full Supabase fresh/upgrade, HTTP, auth, storage or deployed-policy evidence.

- [Visible sheet feedback and lower-right Add verification](VER-QA-029-VISIBLE-FEEDBACK.md).

- [Full-screen form and edge-to-edge sheet verification](VER-QA-030-FORM-PRESENTATION.md).

- [Situation mascot animation verification](VER-QA-031-SITUATION-MASCOTS.md).
