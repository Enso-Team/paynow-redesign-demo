#!/usr/bin/env bash
# Builds the paynow-form micro-frontend and copies its dist into the app's resources.
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
web="$here/../web/app"
dest="$here/DBSDigibank/Resources/PaynowForm"

if [[ ! -d "$web" ]]; then
  echo "sync-form: $web doesn't exist yet. The web workspace builds packages/paynow-form." >&2
  exit 1
fi

pnpm --dir "$web" --filter paynow-form build

dist="$(find "$web/packages/paynow-form" -maxdepth 2 -type d -name dist | head -1)"
if [[ -z "$dist" || ! -f "$dist/index.html" ]]; then
  echo "sync-form: no dist/index.html in packages/paynow-form after the build." >&2
  exit 1
fi

# Clear the old copy but keep .gitkeep, which holds the folder in git so XcodeGen can resolve it.
mkdir -p "$dest"
find "$dest" -mindepth 1 ! -name .gitkeep -delete
cp -R "$dist"/. "$dest"/
echo "sync-form: copied $(find "$dest" -type f ! -name .gitkeep | wc -l | tr -d ' ') files from $dist to $dest"
