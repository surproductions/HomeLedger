#!/usr/bin/env bash
# Installs the simulator build and captures screenshots of the main screens using sample data.
# Usage: capture_screenshots.sh <simulator-udid> <derived-data-path> <output-dir>
set -euo pipefail
UDID="$1"; DD="$2"; OUT="$3"
mkdir -p "$OUT"
APP=$(find "$DD/Build/Products" -maxdepth 3 -path "*iphonesimulator/HomeLedger.app" 2>/dev/null | head -1)
[ -x "$APP/HomeLedger" ] || { echo "No simulator build found; skipping screenshots"; exit 0; }
BUNDLE=com.surproductions.homeledger
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true
xcrun simctl install "$UDID" "$APP"

shot() {
  local name="$1"; shift
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BUNDLE" -UITesting -ResetData -SeedSampleData "$@" >/dev/null
  sleep 6
  xcrun simctl io "$UDID" screenshot "$OUT/$name.png" >/dev/null
  echo "captured $name"
}

xcrun simctl ui "$UDID" appearance light
shot 01-dashboard -StartScreen dashboard
shot 02-my-home -StartScreen myhome
shot 03-maintenance -StartScreen maintenance
shot 04-documents -StartScreen documents
shot 05-asset-detail -StartScreen asset
shot 06-warranties -StartScreen warranties
shot 07-expenses -StartScreen expenses
shot 08-assistant -StartScreen assistant
shot 09-report -StartScreen report
shot 10-settings -StartScreen settings
shot 11-paywall -StartScreen paywall
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
xcrun simctl launch "$UDID" "$BUNDLE" -UITesting -ResetData >/dev/null; sleep 5
xcrun simctl io "$UDID" screenshot "$OUT/00-onboarding.png" >/dev/null
xcrun simctl ui "$UDID" appearance dark
shot 12-dashboard-dark -StartScreen dashboard
shot 13-asset-detail-dark -StartScreen asset
xcrun simctl ui "$UDID" appearance light
xcrun simctl ui "$UDID" content_size extra-extra-extra-large || true
shot 14-dashboard-large-text -StartScreen dashboard
xcrun simctl ui "$UDID" content_size large || true
