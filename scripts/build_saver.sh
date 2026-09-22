#!/bin/bash
# Builds build/MacAttack.saver. Pass --install to copy it to ~/Library/Screen Savers.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
swift build -c release --product MacAttackSaver
LIB="$(swift build -c release --show-bin-path)/libMacAttackSaver.dylib"
SAVER=build/MacAttack.saver
rm -rf "$SAVER"
mkdir -p "$SAVER/Contents/MacOS" "$SAVER/Contents/Resources"
cp "$LIB" "$SAVER/Contents/MacOS/MacAttackSaver"
install_name_tool -id @rpath/MacAttackSaver "$SAVER/Contents/MacOS/MacAttackSaver"
sed "s#__HELPER__#$ROOT/build/MacAttack.app#" Resources/Saver-Info.plist > "$SAVER/Contents/Info.plist"
codesign --force --sign "${SIGN_IDENTITY:--}" --identifier local.macattack.saver "$SAVER" >/dev/null
echo "Built $SAVER"
if [ "${1:-}" = "--install" ]; then
  DEST="$HOME/Library/Screen Savers/MacAttack.saver"
  rm -rf "$DEST"; mkdir -p "$HOME/Library/Screen Savers"; cp -R "$SAVER" "$DEST"
  # make the host pick up the new binary next time
  killall legacyScreenSaver 2>/dev/null || true
  echo "Installed $DEST"
fi
