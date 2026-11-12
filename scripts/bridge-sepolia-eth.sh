#!/usr/bin/env bash
# Official Standard Bridge: Ethereum Sepolia (11155111) -> Base Sepolia (84532).
# Deposits a small amount (~0.2 ETH by default) via the official L1StandardBridge.
# Never prints the private key. Never touches mainnet.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${QDAY_PRIVATE_KEY:-}" ]]; then
  echo "QDAY_PRIVATE_KEY is not set" >&2
  exit 1
fi

exec python3 scripts/bridge_sepolia_eth.py "$@"
