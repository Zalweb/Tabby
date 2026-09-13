# Architecture Decision Records (ADRs)

> **Document:** `docs/DECISIONS.md`  
> **Repository:** [Tabby](https://github.com/Zalweb/Tabby)  
> **Status:** Active Standard

This document records high-impact architectural and technical decisions made for **Tabby**. Each record explains the context, decision, consequences, and alternatives considered to preserve architectural intent across sprints and agent handoffs.

---

## Index of Records

- [ADR-001: Integer Centavo Precision for Philippine Peso Currency Math](#adr-001-integer-centavo-precision-for-philippine-peso-currency-math)
- [ADR-002: Local-First Offline Storage with Background Cloud Sync](#adr-002-local-first-offline-storage-with-background-cloud-sync)
- [ADR-003: Emotion-Driven Financial UI with Mascot State Machine](#adr-003-emotion-driven-financial-ui-with-mascot-state-machine)
- [ADR-004: Non-Custodial Settlement Model with GCash/Maya Intent References](#adr-004-non-custodial-settlement-model-with-gcashmaya-intent-references)
- [ADR-005: Documentation-Driven Multi-Agent Operating Model](#adr-005-documentation-driven-multi-agent-operating-model)

---

## ADR-001: Integer Centavo Precision for Philippine Peso Currency Math

### Status
**Accepted** (2026-09-13)

### Context
Financial apps that represent monetary amounts as standard IEEE-754 floating-point numbers (`number` in JavaScript/TypeScript) frequently suffer from rounding discrepancies (e.g., `0.1 + 0.2 = 0.30000000000000004`). When dividing shared restaurant bills across multiple friends (e.g., ₱1,000 split across 3 people), floating-point errors accumulate, causing balance reconciliation errors and user distrust.

### Decision
1. All monetary values in databases, internal calculations, APIs, and state management stores MUST be represented as **integer centavos** (`1 PHP = 100 centavos`).
2. Splitting operations that yield fractional centavos must explicitly distribute remainder centavos deterministically (e.g., Penny allocation algorithm / largest-remainder method).
3. Decimal formatting (e.g., `₱333.33`) is strictly a presentation-layer transformation performed at the UI boundary.

### Consequences
- **Positive:** Absolute mathematical precision, zero floating-point drift, simple integer database column types (`BIGINT` / `INTEGER`).
- **Negative:** Developers must remember to convert between centavos and display strings when accepting user input.

### Alternatives Considered
- *Floating-Point Numbers (`number` / `float`):* Rejected due to precision leakage during group division.
- *Arbitrary-Precision Decimal Libraries (`decimal.js` / `bignumber.js`):* High bundle size and runtime overhead; unnecessary since Philippine Peso only requires 2 decimal places.

---

## ADR-002: Local-First Offline Storage with Background Cloud Sync

### Status
**Accepted** (2026-09-13)

### Context
In the Philippines, users frequently split dining tabs in locations with degraded cellular connectivity (basement food courts, crowded restaurants, remote vacation spots). If an app requires continuous internet connectivity to log an expense, users abandon the workflow.

### Decision
1. Tabby is architected as a **Local-First** application.
2. Every tab entry, settlement mark, and contact creation is written synchronously to local persistent storage (e.g., SQLite via OPFS/React Native or IndexedDB/WatermelonDB) before any network request is initiated.
3. A background synchronization worker handles pushing changes to the remote cloud datastore (Supabase / Postgres) using conflict-free replicated data strategies (CRDTs or last-write-wins with server timestamps).

### Consequences
- **Positive:** Zero latency UI interactions, 100% offline usability, resilient in poor network conditions.
- **Negative:** Increased complexity in conflict resolution when multiple friends edit the same group tab simultaneously while offline.

### Alternatives Considered
- *Cloud-First REST API:* Rejected because poor connectivity blocks the core user experience during social outings.

---

## ADR-003: Emotion-Driven Financial UI with Mascot State Machine

### Status
**Accepted** (2026-09-13)

### Context
Financial tracking often elicits negative emotions: anxiety about spending, awkwardness asking friends to pay back ("singil"), and guilt over unpaid tabs. Tabby's differentiator is humanizing finance and reducing social awkwardness through its cat mascot.

### Decision
Implement a deterministic Finite State Machine (FSM) for the Tabby mascot character, driving visual expressions based on app state:
- `IDLE_NEUTRAL`: Default state on dashboard when balances are low or stable.
- `CALCULATING`: Active during bill input, splitting, and keypad entry.
- `GENTLE_NUDGE`: Rendered on shareable reminder cards ("Psst! Tab reminder").
- `CELEBRATING`: Triggered upon full settlement ("Bayad na! All settled!").
- `SLEEPING`: Rendered in empty states when active tabs = 0.

### Consequences
- **Positive:** Transforms a stressful chore into an engaging, emotionally positive interaction.
- **Negative:** Requires strict coordination between UI component states and mascot illustration assets.

### Alternatives Considered
- *Static App Logo Only:* Rejected; fails to address the emotional awkwardness of peer debt collection.

---

## ADR-004: Non-Custodial Settlement Model with GCash/Maya Intent References

### Status
**Accepted** (2026-09-13)

### Context
Handling direct fund transfers between users requires money service business (MSB) licenses, Bangko Sentral ng Pilipinas (BSP) compliance, anti-money laundering (AMLA) reporting, and custodial liability. For an MVP peer tracker, this creates immense legal and technical friction.

### Decision
1. Tabby acts strictly as an **accounting ledger and social coordination tool**, NOT a custodial wallet or payment gateway.
2. Tabby facilitates payments by generating payment deep-links, displaying user-provided GCash/Maya QR codes, and attaching transaction reference numbers or receipt screenshots to tab settlements.
3. Settle-up confirmation is double-sided: the payer marks "Bayad na ako" (with reference), and the receiver confirms receipt.

### Consequences
- **Positive:** Zero regulatory licensing overhead, zero security exposure to held funds, immediate time-to-market.
- **Negative:** Users must switch to their GCash or Maya app to send funds rather than completing the transfer inside Tabby.

### Alternatives Considered
- *In-App Wallet / Custodial Balance:* Rejected due to severe BSP regulatory compliance requirements and operational costs.

---

## ADR-005: Documentation-Driven Multi-Agent Operating Model

### Status
**Accepted** (2026-09-13)

### Context
Multiple specialized AI agents and engineering roles collaborate on the codebase across different sessions. Without centralized operating rules, agents hallucinate product specs, deviate from brand tokens, introduce conflicting data formats, or overwrite architectural choices.

### Decision
Maintain a synchronized quartet of documentation files in the repository:
1. [`AGENT.md`](../AGENT.md): Root operational manual and agent role boundaries.
2. [`docs/CHANGELOG.md`](CHANGELOG.md): Historical record of versions and planned features.
3. [`docs/PREFERENCES.md`](PREFERENCES.md): CEO directives, Filipino cultural lexicon, microcopy matrix, and UX guidelines.
4. [`docs/DECISIONS.md`](DECISIONS.md): Architectural Decision Records (ADRs).

### Consequences
- **Positive:** Permanent repository memory, instant onboarding for new agents, zero drift in brand or architectural integrity.
- **Negative:** Agents must proactively update documentation whenever key architectural or product decisions change.
