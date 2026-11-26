# Architecture

```
HomeLedger/
├─ App/              App entry, bootstrap & recovery, AppModel (router/sheets/toasts), RootView, tab bar
├─ DesignSystem/     Theme tokens, reusable components, UIKit bridges (camera, scanner, PDF, share)
├─ Models/           SwiftData @Model types + VersionedSchema + migration plan
├─ Domain/           Pure logic: enums, Money, Recurrence, Warranty, ExpenseCalculator, templates
├─ Persistence/      PersistenceController, FileStore, DataService (mutations & deletion rules), SampleData
├─ Documents/        DocumentImporter, OCRService (Vision/PDFKit), ReceiptParser (rule-based)
├─ Notifications/    ReminderPlanner (pure), NotificationService (reconciler, mockable client)
├─ Search/           SearchService, QueryEngine (local rule-based assistant), RecordRef
├─ Export/           InventoryReportBuilder (PDF), BackupService (versioned JSON), ExportFiles
├─ Store/            StoreConfiguration (product IDs), EntitlementResolver, StoreManager (StoreKit 2)
└─ Features/         SwiftUI screens grouped by feature
```

## Key decisions

**SwiftData, iOS 17 deployment target.** SwiftData gives type-safe models, `@Query`-driven UI and a migration plan with far less code than Core Data. iOS 17 is the first release with SwiftData and `@Observable`; it covers the overwhelming majority of active iPhones while avoiding Core Data boilerplate. Built with Xcode 26.3 / iOS 26.2 SDK.

**CloudKit-ready schema, no sync yet.** Every attribute has a default and every relationship is optional (CloudKit requirements); every record has a stable UUID. Sync is not shipped because it couldn't be validated on real devices and iCloud accounts in this environment — the UI states "Not available yet" rather than showing a fake toggle.

**Files outside the database.** Photos and documents are stored as files in Application Support (`completeUntilFirstUserAuthentication` protection) and referenced by name. Thumbnails are decoded with ImageIO downsampling and cached.

**Explicit deletion rules in `DataService`.** Schema relationships default to `.nullify`; destructive cascades happen in one place, matching the confirmation text the user sees:
- Delete item → photos deleted; documents, repairs, expenses, tasks kept and unlinked.
- Delete room → items become Unassigned.
- Delete home → items (+photos), rooms, tasks deleted; documents, repairs, expenses kept.
- Delete document → file deleted; expenses keep their data.

**Money as integer cents.** Avoids floating-point drift; half-up rounding; currency formatting via `FormatStyle`.

**Recurrence.** Always computed from the original anchor so month-end dates don't drift. Two bases: fixed schedule (skips missed occurrences, never immediately overdue) or count-from-completion. Completing/editing mutates the same task — no duplicates are possible.

**Reminders.** `ReminderPlanner` is a pure function from records → desired notifications with deterministic identifiers (`hl.warranty.<id>.<days>`, `hl.task.<id>`, `hl.followup.<id>`). `NotificationService.sync` removes all `hl.*` pending requests and re-adds the plan, capped at 60 (iOS limit is 64). It never touches other identifiers.

**OCR.** PDFs with a text layer are read via PDFKit; scans/images go through `VNRecognizeTextRequest` (accurate, on-device). `ReceiptParser` returns each field with `detected`/`inferred` confidence and the source line; when nothing matches, the field is empty. Warranty end dates derived from a stated period are flagged as estimates.

**Assistant.** `QueryEngine` matches intents (purchase date, spending, documents, warranties, maintenance due, room contents, counts/value) and answers only from records, always returning supporting `RecordRef`s; otherwise it falls back to keyword search or says it couldn't find the answer. It is labelled as rule-based in the UI.

**Backups.** `BackupArchive` v1 is one JSON document with DTOs for every model plus base64 file blobs. Import is validated (format id, version, duplicate IDs, dangling links, unsafe file names) before any change. Merge inserts missing records and updates only when the backup copy is newer; Replace first writes a safety backup.

**Entitlements.** Derived solely from verified `Transaction.currentEntitlements` through a pure `EntitlementResolver` (revoked/expired grant nothing). No cached "isPremium" flag.

**Failure handling.** If the store can't open, a recovery screen offers retry or "set aside and start fresh" (moves, never deletes).

## Testing
- `HomeLedgerTests` (XCTest, in-memory SwiftData, temp FileStore): models & deletion rules, relaunch persistence, recurrence math, reminders & notification reconciliation (mock center), OCR parser + real Vision/PDFKit pipeline, expenses & money, PDF content, backup round-trip/merge/validation, search & assistant, StoreKit purchase via `SKTestSession`.
- `HomeLedgerUITests`: the seven critical flows from the brief.
- CI (`.github/workflows/ios.yml`): macOS 15 runner, XcodeGen, build-for-testing, unit + UI tests, screenshots, unsigned archive + IPA.
