#!/bin/bash
# Starts the Laya director sidecar. Extra args are passed through (e.g. --parent-pid 123).
DIR="$(cd "$(dirname "$0")" && pwd)"
PY="${LAYA_PYTHON:-$DIR/.venv/bin/python}"
if [ ! -x "$PY" ]; then
  echo "Laya venv missing. Run: python3 -m venv $DIR/.venv && $DIR/.venv/bin/pip install -r $DIR/requirements.txt" >&2
  exit 1
fi
cd "$DIR"
export HF_HUB_OFFLINE="${HF_HUB_OFFLINE:-0}"
export TOKENIZERS_PARALLELISM=false
exec "$PY" server.py "$@"
