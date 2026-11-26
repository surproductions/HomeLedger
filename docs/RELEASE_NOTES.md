## HomeLedger 1.0.0

Your entire home, organized: inventory, documents, warranties, maintenance, repairs, expenses and insurance-ready reports. Local-first and private, with no account required.

### Files in this release
- **HomeLedger-1.0.0-unsigned.ipa**: a Release build that is **not code-signed**. iOS won't install it as-is. Re-sign it with your own Apple ID or certificate (for example with AltStore, Sideloadly or `codesign` plus a provisioning profile), or build from source in Xcode with your Team selected.
- **HomeLedger-1.0.0.xcarchive.zip**: the unsigned Xcode archive. Open it in Xcode Organizer to sign and distribute it with your account.
- **HomeLedger-xcodeproj.zip**: the generated Xcode project. You can also regenerate it with `xcodegen generate`.
- **HomeLedger-screenshots.zip**: simulator screenshots captured by CI.
- **SHA256SUMS.txt**: checksums for the files above.

Built by GitHub Actions on macOS 15 with Xcode 26.3. Unit and UI tests passed in the same workflow run before packaging. Minimum iOS version: 17.0.

### Known limitations
No iCloud sync or household sharing yet. Backups are unencrypted. OCR is rule-based and works best on printed receipts. See the README for details.
