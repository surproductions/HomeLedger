# Changelog

All notable changes to HomeLedger are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [1.0.1] — 2026-11-26

### Added
- Appearance setting: System, Light or Dark (Settings › Appearance).
- The floating tab bar hides while scrolling down and slides back when scrolling up; the selected-tab highlight glides between tabs with a spring animation and icons morph to their filled style.

### Fixed
- Content at the bottom of every screen (e.g. an item's timeline) is no longer hidden behind the tab bar.
- Scroll indicators are hidden throughout the app.
- Full code-review fixes: month-end maintenance drift, snooze/skip scheduling, atomic restore with rollback, reminder permission flow, assistant word matching, parser false positives, editor save safety, trial wording, report filter toggles.

## [1.0.0] — 2026-11-26

### Added
- Onboarding with home creation, optional rooms, privacy explanation, deferred notification permission and removable sample data.
- Dashboard with recorded value, maintenance ring, tappable metrics, highlights, upcoming tasks, expiring warranties, recent items and activity.
- Homes, rooms (reorder/rename/delete), custom categories, Unassigned bucket; multiple homes in Premium.
- Asset inventory with photos, barcode scanning, purchase/warranty/value fields, duplicate, move, archive, delete, timeline and completeness hints.
- Documents from Files/Photos/document camera with on-device OCR and a review screen that labels detected vs inferred values.
- Warranty tracker with per-item reminder intervals and honest unknown/estimated states.
- Maintenance manager with templates, recurrence (fixed schedule or from completion), snooze/skip/complete and history.
- Repair & service records with follow-up reminders and automatically synced expenses.
- Expenses with monthly chart, yearly totals, category breakdown and lifetime cost per item.
- PDF inventory report with filters and include options; share and save to Files.
- Global search and local rule-based "Ask" assistant with supporting records.
- Versioned backup (JSON + embedded files) with validation, merge/replace restore and safety backup.
- StoreKit 2 yearly subscription and lifetime purchase with restore; StoreKit test configuration.
- Settings: profile name, homes, notifications, reminder time, currency, privacy, help, feedback, delete all data.
- Original app icon and launch screen; light and dark appearance; Dynamic Type and VoiceOver support.
- Unit and UI test suites; GitHub Actions CI producing test results, screenshots, an unsigned archive and IPA.
