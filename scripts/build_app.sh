#!/bin/bash
# Builds build/MacAttack.app (SwiftPM + a hand-assembled bundle, since Xcode isn't required).
# The bundle is needed for the standard macOS camera permission prompt (NSCameraUsageDescription).
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
CONFIG="${CONFIG:-release}"

# --- signing -----------------------------------------------------------------
# Ad-hoc by default. Set SIGN_IDENTITY to a Developer ID to produce a build that
# can be notarized (see "Signing & notarizing" in the README).
sign_bundle() {
  local target="$1" identifier="$2"
  local identity="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application/{print $2; exit}')}"
  if [ -n "$identity" ] && [ "$identity" != "-" ]; then
    codesign --force --timestamp --options runtime \
      --entitlements "$ROOT/Resources/MacAttack.entitlements" \
      --sign "$identity" --identifier "$identifier" "$target"
    echo "signed $target as $identity (hardened runtime)"
  else
    codesign --force --sign - --identifier "$identifier" "$target" >/dev/null
    echo "signed $target ad-hoc (unsigned build: Gatekeeper will warn)"
  fi
}

swift build -c "$CONFIG" --product MacAttack
BIN="$(swift build -c "$CONFIG" --show-bin-path)/MacAttack"
APP="$ROOT/build/MacAttack.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MacAttack"
# ship the sidecar inside the bundle (without any venv: that is created on first setup)
mkdir -p "$APP/Contents/Resources/LayaDirector"
cp LayaDirector/server.py LayaDirector/questions.py LayaDirector/run.sh LayaDirector/requirements.txt "$APP/Contents/Resources/LayaDirector/"
cp scripts/setup_laya.sh "$APP/Contents/Resources/LayaDirector/"
chmod +x "$APP/Contents/Resources/LayaDirector/run.sh" "$APP/Contents/Resources/LayaDirector/setup_laya.sh"
sed "s#__LAYA_DIR__#$ROOT/LayaDirector#" Resources/Info.plist > "$APP/Contents/Info.plist"
sign_bundle "$APP" local.macattack
echo "Built $APP"
