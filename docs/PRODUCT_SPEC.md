# HomeLedger — Product Specification (v1.0)

**Tagline:** Your entire home, organized.
**Platform:** iPhone (iOS 17+), native SwiftUI.
**Primary user:** Homeowners and renters who want one dependable place for what they own, the paperwork behind it, and the upkeep it needs.

## 1. Market research summary (November 2026)

A short desk-research pass over public comparisons and App Store listings of home-inventory, maintenance and warranty apps (Sortly, Encircle, HomeZada, Nest Egg, Itemtopia, Under My Roof, HomeBox, Havault and others) found:

| Pattern | Observation |
|---|---|
| **What works** | Photo-first item capture; insurance-oriented PDF/CSV exports (Encircle, Sortly); warranty-expiry reminders (Nest Egg, Havault — e.g. 90/30/7-day alerts); combined inventory + maintenance + budgeting (HomeZada). |
| **Common complaints** | Business/SKU-oriented UX for households (Sortly); steep learning curve and web-first design (HomeZada); quote-based or professional pricing (Encircle); maintenance reminders locked behind high tiers; accounts required; apps shutting down and stranding data (Centriq). |
| **Pricing patterns** | Free tiers with small item limits; subscriptions from ~$5–10/month for all-in-one suites; some one-time purchases (~$7); business tiers $49+/month. |
| **Opportunity** | Few apps combine *fast capture + document intelligence + warranty and maintenance reminders + repair history + insurance-ready export* in a calm, offline, privacy-first iPhone app with no account. Data portability (open backup format) directly addresses the "app shut down" fear. |

The category is crowded — HomeLedger does not assume an empty market. It competes on cohesion, trust and polish rather than feature count.

## 2. Differentiators

1. **Fast visual capture** — camera/library photos, barcode scan, duplicate-from-similar.
2. **Honest document intelligence** — on-device OCR with per-field "Detected" vs "Best guess" labels; nothing is silently filled in.
3. **Warranty + maintenance reminders** — per-item intervals, deterministic local notifications (no duplicates).
4. **Repair & ownership history** — a per-item timeline; repair costs flow into expenses automatically.
5. **Insurance-ready PDF** — clearly labelled as a personal record, not an appraisal.
6. **Privacy-first, offline** — no account, no analytics, no network calls except the App Store.
7. **Calm premium design** — royal-blue hero surfaces, soft neutral canvas, color used only for status.

## 3. MVP scope (shipped in 1.0)

- Onboarding (skippable sample-data mode, home + rooms, plain-language privacy, deferred notification prompt)
- Dashboard with tappable metrics and quick actions
- Homes, rooms, custom categories; asset inventory with full field set
- Documents: Files / Photos / document-camera import, on-device OCR, review-before-save
- Warranty tracker (expiring soon / active / expired / unknown)
- Maintenance manager (templates, recurrence by schedule or completion, snooze/skip/complete, history)
- Repair & service history with linked expenses and follow-up reminders
- Expenses with monthly/annual summaries and charts
- Global search and a rule-based "Ask" assistant over local records
- PDF inventory report; share sheet + save to Files
- Versioned JSON backup with merge/replace restore and automatic safety backup
- StoreKit 2 Premium (yearly + lifetime) with restore

## 4. Free vs Premium

| Free | Premium |
|---|---|
| 1 home, up to 25 active items | Unlimited items, multiple homes |
| Documents + on-device OCR review | Photo-rich PDF reports + replacement values |
| Warranty reminders (30/14/7 days) | Custom reminder intervals per item |
| Maintenance reminders, repair log | Expense category breakdowns, multi-year trends |
| Search, assistant, backups, full text PDF | — |

Existing records are never paywalled: archived/over-limit items remain viewable, editable and exportable.

*Deviation from the brief:* OCR-assisted extraction is **free** rather than Premium. Extraction is HomeLedger's most distinctive, privacy-preserving capability and the best demonstration of value; gating it would push new users back to manual entry.

**Pricing experiment:** $29.99/year (1-week free trial) vs $59.99 lifetime. Prices live in App Store Connect only; IDs in `HomeLedger/Store/StoreConfiguration.swift`.

## 5. Roadmap (not in 1.0)

- Optional iCloud sync (CloudKit mirror; schema is already CloudKit-compatible) with conflict UI
- Household sharing (CKShare)
- Encrypted backups (password-protected)
- Landlord mode: multiple units, tenant-facing maintenance requests
- Widgets and Siri/App Intents ("What's due this week?")
- iPad layout
