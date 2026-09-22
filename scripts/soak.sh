#!/bin/bash
# Stability soak: runs an isolated instance (own Laya port) in simulation autopilot + chaos,
# samples CPU/RSS, kills Laya mid-run, freezes it (slow/hung Laya), then SIGTERMs the app and
# checks nothing is left running.   Usage: scripts/soak.sh [minutes=30]
set -u
cd "$(dirname "$0")/.."
MIN="${1:-30}"; PORT=8790
OUT="build/soak-$(date +%Y%m%d-%H%M%S).csv"
LOGS="$HOME/Library/Logs/MacAttack"; rm -f "$LOGS/stats-$PORT.log"
BIN=build/MacAttack.app/Contents/MacOS/MacAttack
"$BIN" --autopilot --chaos --no-sound --debug --no-activate --laya-port $PORT >/dev/null 2>&1 &
APP=$!
echo "t_s,app_cpu,app_rss_mb,laya_pid,laya_cpu,laya_rss_mb,event" > "$OUT"
end=$((MIN * 60)); t=0; ev=""
kill_at=$((end * 27 / 100)); stop_at=$((end * 55 / 100)); cont_at=$((stop_at + 60))
while [ $t -le $end ]; do
  LP=$(pgrep -f "server.py --port $PORT" | head -1)
  if [ $t -ge $kill_at ] && [ $t -lt $((kill_at + 30)) ] && [ -n "$LP" ]; then kill "$LP"; ev="killed_laya"; fi
  if [ $t -ge $stop_at ] && [ $t -lt $((stop_at + 30)) ] && [ -n "$LP" ]; then kill -STOP "$LP"; ev="froze_laya"; fi
  if [ $t -ge $cont_at ] && [ $t -lt $((cont_at + 30)) ] && [ -n "$LP" ]; then kill -CONT "$LP"; ev="thawed_laya"; fi
  A=$(ps -o %cpu=,rss= -p $APP 2>/dev/null) || { wait $APP; echo "APP DIED at ${t}s (exit status $?; >128 means signal N-128)" | tee -a "$OUT"; exit 1; }
  L=$( [ -n "$LP" ] && ps -o %cpu=,rss= -p "$LP" 2>/dev/null || echo "0 0")
  echo "$t,$(echo $A | awk '{print $1","int($2/1024)}'),${LP:-none},$(echo $L | awk '{print $1","int($2/1024)}'),$ev" >> "$OUT"
  ev=""; sleep 30; t=$((t + 30))
done
kill -TERM $APP; sleep 5
LEFT=$(pgrep -f "server.py --port $PORT")
echo "app exited: $(ps -p $APP >/dev/null && echo NO || echo yes); sidecar left: ${LEFT:-none}" | tee -a "$OUT"
echo "csv: $OUT"; echo "stats: $LOGS/stats-$PORT.log"
