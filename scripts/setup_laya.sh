#!/bin/bash
# One-time Laya setup: a private virtualenv plus the model checkpoint (~2.5 GB total).
# Everything lands in ~/Library/Application Support/MacAttack and can be deleted to undo.
set -u
SUPPORT="$HOME/Library/Application Support/MacAttack"
VENV="$SUPPORT/laya-venv"
DIR="$(cd "$(dirname "$0")" && pwd)"
[ -f "$DIR/requirements.txt" ] || DIR="$DIR/../LayaDirector"
mkdir -p "$SUPPORT"
echo "==> Looking for Python 3.10+"
PY=""
for c in python3.13 python3.12 python3.11 python3.10 python3; do
  p=$(command -v $c 2>/dev/null) || continue
  v=$("$p" -c 'import sys;print(sys.version_info[0]*100+sys.version_info[1])' 2>/dev/null) || continue
  if [ "${v:-0}" -ge 310 ]; then PY="$p"; break; fi
done
if [ -z "$PY" ]; then
  echo "!! No Python 3.10+ found. Install it (e.g. from python.org or 'brew install python') and run this again." >&2
  exit 1
fi
echo "    using $PY"
echo "==> Creating virtualenv at $VENV"
"$PY" -m venv "$VENV" || exit 1
echo "==> Installing laya, fastapi, uvicorn (this downloads PyTorch, a few hundred MB)"
"$VENV/bin/pip" install --upgrade pip >/dev/null 2>&1
"$VENV/bin/pip" install -r "$DIR/requirements.txt" || exit 1
echo "==> Downloading the Laya checkpoint (~2.2 GB, cached in ~/.cache/huggingface)"
"$VENV/bin/python" - <<'PYEOF' || exit 1
from laya import Router
r = Router(max_loaded=1)
r.load("english")
print("checkpoint ready")
PYEOF
echo "==> Done. Mac Attack will use Laya from now on."
