#!/usr/bin/env bash
# Builds a copy of the app with the art in ART_DIR (an Assets.xcassets folder) and installs it on an iPhone.
# The copy lives in a temp directory, so the art stays out of this public repo.
#   ART_DIR=~/path/Assets.xcassets scripts/install-phone.sh <device-udid>
set -euo pipefail
device="${1:?device udid, from: xcrun devicectl list devices}"
here="$(cd "$(dirname "$0")/.." && pwd)"
work="${TMPDIR:-/tmp}/paynow-phone"
mkdir -p "$work/ios"
rsync -a --delete --exclude '*.xcodeproj' "$here/" "$work/ios/"
if [ -n "${ART_DIR:-}" ]; then rsync -a "$ART_DIR/" "$work/ios/DBSDigibank/Resources/Assets.xcassets/"; fi
cd "$work/ios"
xcodegen generate -q
xcodebuild build -quiet -project DBSDigibank.xcodeproj -scheme DBSDigibank -destination 'generic/platform=iOS' \
  -derivedDataPath "$work/build" -allowProvisioningUpdates
xcrun devicectl device install app --device "$device" "$work/build/Build/Products/Debug-iphoneos/digibank.app"
xcrun devicectl device process launch --terminate-existing --device "$device" sg.demo.digibank
