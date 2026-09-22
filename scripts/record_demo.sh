#!/bin/bash
# Records a Simulation-Mode demo of Mac Attack (no camera, no faces) and crops it to the app
# window, so nothing else on your desktop ends up in the file.
#   scripts/record_demo.sh [seconds=50]
set -euo pipefail
cd "$(dirname "$0")/.."
SECS="${1:-50}"
OUT="build/mac-attack-demo.mp4"
RAW="build/.demo-raw.mov"
mkdir -p build
pkill -f "MacAttack --simulate" 2>/dev/null || true   # never touch the --helper instance
sleep 1
open build/MacAttack.app --args --simulate --debug --no-sound
sleep 5
# window bounds in points, and the screen scale, so the crop lands exactly on the window
read -r X Y W H < <(osascript -e 'tell application "System Events" to tell process "MacAttack" to get {position, size} of window 1' | tr ',' ' ' | awk '{print $1, $2, $3, $4}')
echo "window: ${W}x${H} at ${X},${Y}"
screencapture -v -V "$SECS" -D 1 "$RAW" &
REC=$!
sleep 1
osascript scripts/demo_actions.applescript || true
wait $REC
# crop (screen is Retina: raw pixels are 2x the point values)
ffmpeg -y -loglevel error -i "$RAW" -vf "crop=$((W*2)):$((H*2)):$((X*2)):$((Y*2)),scale=1440:-2" -c:v libx264 -crf 20 -pix_fmt yuv420p "$OUT"
rm -f "$RAW"
echo "wrote $OUT"
