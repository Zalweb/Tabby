# Tabby Brand Guide & Design Tokens

> **Tagline:** *"Keep tabs. Settle up."*

This document defines the brand identity, visual guidelines, color palette, design tokens, and character system for **Tabby** — a friendly, stress-free personal and social financial tracking application designed for tracking shared expenses, debts ("utang"), reminders, and settlements.

---

## 1. Brand Overview

- **Product Name:** Tabby
- **Tagline:** "Keep tabs. Settle up."
- **Core Purpose:** Make tracking shared costs, peer-to-peer debts ("utang"), and settlements intuitive, warm, and socially frictionless.
- **Tone & Voice:** Friendly, approachable, reliable, lighthearted yet organized. Financial tracking shouldn't feel stressful or confrontational.

---

## 2. Visual Assets

All canonical branding assets are housed under `assets/branding/`:

| Asset File | Description | Usage |
| :--- | :--- | :--- |
| [`tabby-icon.jpg`](tabby-icon.jpg) | Main Tabby App Icon & Logo | App launcher icon, splash screens, navbar branding, favicon |
| [`tabby-mascot-sheet.jpg`](tabby-mascot-sheet.jpg) | Character Expression & System Sheet | Onboarding, empty states, settlement celebrations, reminders, notifications |

---

## 3. Color Palette & Design Tokens

### Primary Palette

| Token Name | Hex Code | RGB | Role / Usage |
| :--- | :--- | :--- | :--- |
| **Charcoal Primary** | `#1F1F1F` | `rgb(31, 31, 31)` | Primary typography, headers, dark UI cards, high-contrast buttons |
| **Accent Highlight** | `#FFB74D` | `rgb(255, 183, 77)` | Warm amber accent, mascot details, CTA highlights, pending status, badges |
| **Background Light** | `#F8F8F8` | `rgb(248, 248, 248)` | App canvas background, light mode surface, clean spacing |
| **Secondary Text/Icons** | `#9CA3AF` | `rgb(156, 163, 175)` | Secondary metadata, captions, inactive tab icons, borders/dividers |

### Extended Palette Recommendations

| Token Name | Hex Code | Role / Usage |
| :--- | :--- | :--- |
| **Surface White** | `#FFFFFF` | Card surfaces, modals, input containers |
| **Success / Settled Green** | `#34D399` / `#10B981` | "Settled" / paid status, positive balance, completed transactions |
| **Alert / Debt Red** | `#F87171` / `#EF4444` | Overdue tabs, urgent balance alerts |

### Code Implementation Snippets

#### CSS Variables
```css
:root {
  --tabby-primary: #1F1F1F;
  --tabby-accent: #FFB74D;
  --tabby-bg-light: #F8F8F8;
  --tabby-secondary: #9CA3AF;
  --tabby-surface: #FFFFFF;
}
```

#### Tailwind CSS Configuration
```js
// tailwind.config.js
module.exports = {
  theme: {
    extend: {
      colors: {
        tabby: {
          charcoal: '#1F1F1F',
          accent: '#FFB74D',
          light: '#F8F8F8',
          muted: '#9CA3AF',
        }
      }
    }
  }
}
```

---

## 4. Mascot & Character System

The Tabby mascot is an expressive, friendly cat character that humanizes debt and expense tracking, defusing the social awkwardness around money:

### Character Roles & Expressions
1. **Neutral / Welcoming:**
   - Default dashboard companion, greeting users and introducing new features.
2. **Calculating / Logging:**
   - Shown during bill splitting, expense entry, and calculator interactions.
3. **Gentle Reminder ("Tab Notification"):**
   - Soft, polite nudge for pending utang/bills without guilt or tension.
4. **Celebratory / Settled:**
   - Joyful expression when a balance reaches ₱0.00 ("All settled up!").
5. **Empty State:**
   - Relaxed cat nap when there are no active debts or pending tasks.

---

## 5. Domain Concepts & Localization

- **Currency:** Philippine Peso (`₱` / PHP) is the first-class default currency format.
- **Cultural Context ("Utang" & "Settle Up"):**
  - Respects Filipino social dynamics around borrowing, lending, and dining together.
  - Normalizes tracking without awkward confrontation by replacing stressful collection with clear, shared tabs and automated, gentle reminders.
- **Key Flows:**
  - Expense Logging: Quick splitting of meals, group bills, and utilities.
  - Utang Tracking: Clear distinction between *"You are owed"* and *"You owe"*.
  - Settle Up: One-tap settlement confirmation with payment channel references (e.g. GCash, Maya, Cash).
