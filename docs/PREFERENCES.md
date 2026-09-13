# Tabby Product Preferences & Cultural Tone Guide

> **Document:** `docs/PREFERENCES.md`  
> **Status:** Active / Living Document  
> **Scope:** Brand Tone, Cultural Nuances, CEO Directives, User Experience Heuristics, and Microcopy Rules.

---

## 1. Executive Philosophy & CEO Directives

Money between friends and family is sensitive. The core philosophy of **Tabby** is **"Friendship First, Accounting Second."**

### Core Directives
1. **Never Weaponize Debts:** The app must never sound like a debt collector, a bank, or a legal demand letter. No red warning banners for regular pending tabs.
2. **Defuse Awkwardness with Warmth:** Asking friends for money is socially uncomfortable in the Philippines ("nakakahiya maningil"). Tabby absorbs that social tension through cute, disarming mascot animations, lighthearted reminders, and clear settlement links.
3. **Speed is King:** Logging who paid for lunch must take under 5 seconds. If logging takes too long, users will fall back to disorganized Messenger group chats or forget entirely.
4. **Philippine-First Context:** The app is built from the ground up for the Philippine financial ecosystem (PHP `₱`, GCash, Maya, Cash, KKB dining habits).

### CEO Conversation & Decisions Log

| Date | Stakeholder / Source | Directive / Decision | Rationale | Impacted Areas |
| :--- | :--- | :--- | :--- | :--- |
| **2026-09-13** | CEO / Product Lead | Adopt *"Keep tabs. Settle up."* as official tagline. | Simple, punchy, action-oriented, universally understood. | Branding, Splash screen, App Store metadata. |
| **2026-09-13** | CEO / Product Lead | Mascot must have turnaround views and explicit emotion states. | Humanizes transactions; visually signals zero-balance celebration ("Bayad na!"). | Mascot assets, UI empty states, animation hooks. |
| **2026-09-13** | CEO / Product Lead | Prioritize GCash & Maya as primary settlement references over credit cards. | GCash & Maya are the de facto P2P payment rails for Filipino peer groups. | Settlement flow, QR code viewer, receipt sharing. |
| **2026-09-13** | CEO / Product Lead | Enforce integer centavo calculations for all currency values. | Prevents IEEE-754 floating point rounding drift when splitting odd bills. | Ledger database, Calculation engine, API contracts. |

---

## 2. Filipino Cultural Lexicon & Etiquette Matrix

In the Philippines, peer financial interactions have rich social etiquette. Agents and developers must understand and correctly implement these concepts:

| Term / Concept | Cultural Meaning | Tabby Implementation | DO NOT Use |
| :--- | :--- | :--- | :--- |
| **Utang** | Debt or borrowed money. Carries slight social friction or shame if emphasized coldly. | Reframe as an open "Tab" or "Paki-settle". Keep it neutral and companionable. | "Delinquent debt", "Arrears", "Defaulter". |
| **Bayad na ako** | "I have already paid" / Confirmed settlement. | Tap-to-confirm settlement banner. Emits celebration confetti and joyful cat mascot. | "Payment cleared by creditor". |
| **KKB** | *Kanya-Kanyang Bayad* ("Each pays their own" / Go Dutch). | Dedicated 1-tap bill split mode dividing the total bill evenly or per-item with auto-tax/service charge distribution. | "Individual liability partition". |
| **Abono / Salo** | Covering someone's share upfront when they lack cash or change. | "Covered by [Name]" tag with quick 1-click repayment tab creation. | "Credit extension", "Underwriting". |
| **Libre** | A genuine treat/gift where repayment is explicitly NOT expected. | "Mark as Libre" toggle which removes the amount from net debt balances and files it under "Treats". | Treating it as a zero-interest loan. |
| **Maningil / Nudge** | Asking for payment. Typically creates social hesitation ("hiya"). | Friendly pre-composed shareable cards with cute mascot saying: *"Psst! Pasuyo nung tab natin for [Lunch] 🐾"* | Aggressive collection demands or countdown timers. |
| **Sukli** | Change from cash transactions. | Exact centavo split rounder (options to round up to nearest ₱5 or ₱10 for cash ease). | Ignoring cash divisibility. |

---

## 3. Microcopy & Tone of Voice

### Voice Pillars
1. **Friendly & Disarming:** Like a reliable barkada friend holding the group's receipts.
2. **Empathetic & Polite:** Respects the user's relationships; never shames or alarms.
3. **Conversational Taglish / Modern English:** Natural phrasing used by young professionals, college students, and barkadas.

### Microcopy Comparison Matrix

| Context | ❌ Cold / Corporate (Avoid) | ✅ Tabby Way (Adopt) |
| :--- | :--- | :--- |
| **Dashboard Summary (Owed)** | "Total Debt Outstanding: ₱450.00" | "You're owed **₱450.00** across 2 friends" |
| **Dashboard Summary (Owing)** | "You are in debt: ₱250.00" | "You have **₱250.00** in active tabs to settle" |
| **Gentle Reminder Button** | "Send Collection Notice" | "Send Gentle Nudge 🐾" / "Pasuyo Reminder" |
| **Reminder Message (Shareable)**| "Notice: You owe [User] ₱250. Pay immediately." | "Hey! Here's our tab for milk tea (₱250). Settle up whenever you're ready! [Link] 🐱" |
| **Settlement Confirmation** | "Transaction completed. Balance zeroed." | "All settled up! Salamat! 🎉" |
| **Zero Debt State** | "No records found in database." | "All tabs cleared! Time for a cat nap. 😴" |
| **Equal Split Action** | "Execute Split by N" | "Split Equally (KKB)" |

---

## 4. Visual & UI/UX Preferences

### Layout & Ergonomics
- **Mobile-First Touch Targets:** Minimum 48x48px interactive areas for fast thumb interactions.
- **Card-Based Hierarchy:** Crisp white surfaces (`#FFFFFF`) on subtle canvas (`#F8F8F8`) with warm amber accents (`#FFB74D`).
- **Mascot Presence:**
  - **Header / Dashboard:** Mascot greets user with contextual reaction based on net balance.
  - **Settled Dialog:** Animated mascot giving a high-five or thumbs up.
  - **Empty Tabs View:** Sleeping mascot illustration.

### Currency Formatting Rules
- Always prefix Philippine currency with `₱` (U+20B1) followed by a non-breaking space or standard spacing.
- Always display 2 decimal places for financial totals (e.g., `₱1,250.00`).
- Use comma thousands separators: `₱12,500.50`.

---

## 5. Decision & Governance Protocol

Whenever a new user preference or CEO product directive is communicated:
1. Log the date, stakeholder, decision, and rationale in Section 1 of this document.
2. If the directive alters system architecture or data storage, document the technical implementation in [`docs/DECISIONS.md`](DECISIONS.md).
3. Record the version bump or feature addition in [`docs/CHANGELOG.md`](CHANGELOG.md).
