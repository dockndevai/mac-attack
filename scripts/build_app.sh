#!/bin/bash
# Builds build/MacAttack.app (SwiftPM + a hand-assembled bundle, since Xcode isn't required).
# The bundle is needed for the standard macOS camera permission prompt (NSCameraUsageDescription).
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
CONFIG="${CONFIG:-release}"
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
# Prefer a stable signing identity (keeps camera permission across rebuilds); fall back to ad-hoc.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development|Developer ID/{print $2; exit}')}"
codesign --force --sign "${IDENTITY:--}" --identifier local.macattack "$APP" >/dev/null
echo "Built $APP (signed: ${IDENTITY:-ad-hoc})"
