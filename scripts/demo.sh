#!/usr/bin/env bash
# Local end-to-end demo: Anvil + vault + x402 research payment + allocate + reserve-breach.
# Does not use QDAY_PRIVATE_KEY. Uses Anvil's well-known account #0.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ANVIL_PORT="${ANVIL_PORT:-8545}"
SERVICE_PORT="${PORT:-4021}"
UI_PORT="${UI_PORT:-8788}"
RPC_URL="${RPC_URL:-http://127.0.0.1:${ANVIL_PORT}}"
export RPC_URL NETWORK=anvil
# Public Anvil test key (account #0). Not a secret.
export LOCAL_PRIVATE_KEY="${LOCAL_PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"

mkdir -p deployments tools/web .logs

started_anvil=0
if ! curl -s -m 1 -X POST -H 'Content-Type: application/json' \
    --data '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' \
    "$RPC_URL" >/dev/null 2>&1; then
  echo "starting anvil on :${ANVIL_PORT}"
  anvil --port "$ANVIL_PORT" --chain-id 31337 --block-time 1 > .logs/anvil.log 2>&1 &
  echo $! > .logs/anvil.pid
  started_anvil=1
  for i in $(seq 1 40); do
    if curl -s -m 1 -X POST -H 'Content-Type: application/json' \
        --data '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' \
        "$RPC_URL" >/dev/null 2>&1; then
      break
    fi
    sleep 0.15
  done
fi

echo "deploying local stack"
forge script script/DeployLocal.s.sol --rpc-url "$RPC_URL" --broadcast --slow -q

echo "starting x402 research API on :${SERVICE_PORT}"
python3 tools/service/server.py > .logs/service.log 2>&1 &
echo $! > .logs/service.pid
for i in $(seq 1 40); do
  if curl -s -m 1 "http://127.0.0.1:${SERVICE_PORT}/health" >/dev/null 2>&1; then
    break
  fi
  sleep 0.15
done

echo "running agent loop"
set +e
python3 tools/agent/run.py
agent_rc=$?
set -e

echo "serving dashboard on :${UI_PORT} (Ctrl-C to stop if you started this in the foreground)"
# Leave the dashboard running only if DEMO_KEEP_UI=1; otherwise print how to open it.
if [[ "${DEMO_KEEP_UI:-0}" == "1" ]]; then
  python3 -m http.server "$UI_PORT" --bind 127.0.0.1 --directory tools/web
else
  echo "dashboard files: $ROOT/tools/web/index.html"
  echo "open with:  python3 -m http.server ${UI_PORT} --bind 127.0.0.1 --directory tools/web"
  echo "snapshot:   $ROOT/tools/web/snapshot.json"
fi

exit "$agent_rc"
