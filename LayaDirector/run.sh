#!/bin/bash
# Starts the Laya director sidecar. Extra args are passed through (e.g. --parent-pid 123).
#
# Virtualenv lookup order:
#   $LAYA_VENV                                   (explicit override)
#   <this dir>/.venv                             (developer checkout)
#   ~/Library/Application Support/MacAttack/laya-venv   (installed app: the bundle is read-only)
DIR="$(cd "$(dirname "$0")" && pwd)"
SUPPORT="$HOME/Library/Application Support/MacAttack/laya-venv"
if [ -n "${LAYA_VENV:-}" ]; then VENV="$LAYA_VENV"
elif [ -x "$DIR/.venv/bin/python" ]; then VENV="$DIR/.venv"
else VENV="$SUPPORT"; fi
PY="$VENV/bin/python"
if [ ! -x "$PY" ]; then
  echo "Laya is not set up yet. In Mac Attack: Debug Mode → LAYA → Set Up Laya." >&2
  echo "(or run: scripts/setup_laya.sh)" >&2
  exit 2
fi
cd "$DIR"
export TOKENIZERS_PARALLELISM=false
exec "$PY" server.py "$@"
