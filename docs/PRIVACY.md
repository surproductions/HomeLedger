# HomeLedger Privacy Policy (draft)

_Last updated: November 2026. This is a draft for review before App Store submission._

## Summary
HomeLedger is designed to work entirely on your iPhone. We don't operate servers that receive your data, we don't require an account, and the app contains no advertising or analytics SDKs.

## Data you enter
Homes, rooms, items, photos, documents (and text recognized from them), warranties, maintenance tasks, repair records and expenses are stored in the app's private storage on your device and protected by iOS Data Protection.

## Data flow
| Data | Where it goes |
|---|---|
| Records, photos, documents | Stay on device. Included in your normal iCloud/computer device backup if you have that enabled in iOS. |
| Document text recognition | Performed on-device by Apple's Vision framework. Not transmitted. |
| Reminders | Scheduled locally with iOS notifications. |
| Reports & backups | Created on device. Leave the device only when **you** share or save them elsewhere. Backups are not encrypted by HomeLedger — store them somewhere you trust. |
| Purchases | Handled by Apple. HomeLedger receives only whether Premium is active. |
| Feedback link | Opens GitHub Issues in your browser; nothing is sent automatically. |

HomeLedger makes no network requests of its own other than StoreKit (App Store) calls.

## Optional cloud features
iCloud sync and household sharing are not available in version 1.0. If they're added, this policy will describe exactly what syncs, and they will be opt-in. If any cloud AI feature is ever offered, it will require explicit consent and disclose exactly what is transmitted.

## Your control
- Edit or delete any record at any time.
- Export everything via Settings › Back up & restore.
- Delete all data via Settings › Delete all data, or by deleting the app.

## Children
HomeLedger is not directed at children and collects no personal data from anyone.

## Contact
Open an issue at https://github.com/surproductions/HomeLedger/issues.
