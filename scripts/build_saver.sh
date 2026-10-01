#!/bin/bash
# Builds build/MacAttack.saver. Pass --install to copy it to ~/Library/Screen Savers.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
ROOT="$(pwd)"
swift build -c release --product MacAttackSaver
LIB="$(swift build -c release --show-bin-path)/libMacAttackSaver.dylib"
SAVER=build/MacAttack.saver
rm -rf "$SAVER"
mkdir -p "$SAVER/Contents/MacOS" "$SAVER/Contents/Resources"
cp "$LIB" "$SAVER/Contents/MacOS/MacAttackSaver"
install_name_tool -id @rpath/MacAttackSaver "$SAVER/Contents/MacOS/MacAttackSaver"
sed "s#__HELPER__#$ROOT/build/MacAttack.app#" Resources/Saver-Info.plist > "$SAVER/Contents/Info.plist"

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

sign_bundle "$SAVER" local.macattack.saver
echo "Built $SAVER"
if [ "${1:-}" = "--install" ]; then
  DEST="$HOME/Library/Screen Savers/MacAttack.saver"
  rm -rf "$DEST"; mkdir -p "$HOME/Library/Screen Savers"; cp -R "$SAVER" "$DEST"
  # make the host pick up the new binary next time
  killall legacyScreenSaver 2>/dev/null || true
  echo "Installed $DEST"
fi
