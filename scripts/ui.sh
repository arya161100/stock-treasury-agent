#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
PORT="${PORT:-8788}"
HOST="${HOST:-127.0.0.1}"
echo "dashboard at http://${HOST}:${PORT}/"
exec python3 -m http.server "$PORT" --bind "$HOST" --directory tools/web
