#!/bin/bash
# Builds build/MacAttack-<version>.dmg containing the app, the screensaver and a one-click installer.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:-0.1.0}"
STAGE="build/dmg"
DMG="build/MacAttack-$VERSION.dmg"
./scripts/build_app.sh
./scripts/build_saver.sh
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R build/MacAttack.app "$STAGE/"
cp -R build/MacAttack.saver "$STAGE/"
ln -s /Applications "$STAGE/Applications"

cat > "$STAGE/Install.command" <<'EOF'
#!/bin/bash
# Installs Mac Attack: the app into /Applications and the screensaver into your user Screen Savers.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
echo "Installing Mac Attack…"
rm -rf "/Applications/MacAttack.app"
cp -R "$HERE/MacAttack.app" /Applications/
mkdir -p "$HOME/Library/Screen Savers"
rm -rf "$HOME/Library/Screen Savers/MacAttack.saver"
cp -R "$HERE/MacAttack.saver" "$HOME/Library/Screen Savers/"
xattr -dr com.apple.quarantine "/Applications/MacAttack.app" "$HOME/Library/Screen Savers/MacAttack.saver" 2>/dev/null || true
echo
echo "Installed."
echo "  1. Open /Applications/MacAttack.app and allow the camera."
echo "  2. Tick Debug Mode → LAYA → 'Set Up Laya' (one-time, ~2.5 GB) for the model director."
echo "     (Skip it and the game runs on its built-in random director.)"
echo "  3. Debug Mode → SCREENSAVER HELPER → 'Install Helper' to use the screensaver."
echo "  4. System Settings › Screen Saver › Mac Attack."
echo
read -n 1 -s -r -p "Press any key to close."
open /Applications/MacAttack.app
EOF
chmod +x "$STAGE/Install.command"

cat > "$STAGE/READ ME FIRST.txt" <<'EOF'
MAC ATTACK — a screensaver that throws rubber ducks at you
==========================================================

QUICK INSTALL
  Double-click "Install.command".
  macOS may block it: right-click → Open → Open.

MANUAL INSTALL
  Drag MacAttack.app to Applications.
  Double-click MacAttack.saver (installs for your user).

AFTER INSTALLING
  1. Open Mac Attack and allow camera access.
  2. Debug Mode → LAYA → "Set Up Laya" (optional, one-time ~2.5 GB, needs Python 3.10+).
     Without it the game still runs, using its own local random director.
  3. Debug Mode → SCREENSAVER HELPER → "Install Helper".
     The screensaver needs this: macOS never gives a screensaver camera access, so a small
     helper owns the camera and sends only anonymous boxes over 127.0.0.1.
  4. System Settings › Screen Saver › Mac Attack.

PRIVACY
  Everything runs on this Mac. Body rectangles only, no face recognition, no recording,
  nothing uploaded. The camera stays off unless the screensaver is on screen.

UNSIGNED BUILD
  Built without an Apple Developer ID, so Gatekeeper will warn and macOS may re-ask for
  camera permission after updates.

UNINSTALL
  Remove Helper in the app, delete /Applications/MacAttack.app,
  ~/Library/Screen Savers/MacAttack.saver and ~/Library/Application Support/MacAttack.
EOF

hdiutil create -quiet -volname "Mac Attack $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
echo "Built $DMG ($(du -h "$DMG" | cut -f1))"
