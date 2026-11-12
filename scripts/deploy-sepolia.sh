#!/usr/bin/env bash
# Deploy to Base Sepolia (84532) ONLY. The key is read from the environment
# inside the Forge script (vm.envUint) and is never printed or passed on the CLI.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${QDAY_PRIVATE_KEY:-}" ]]; then
  echo "QDAY_PRIVATE_KEY is not set" >&2
  exit 1
fi

RPC="${BASE_SEPOLIA_RPC:-https://sepolia.base.org}"
CHAIN="$(cast chain-id --rpc-url "$RPC")"
if [[ "$CHAIN" != "84532" ]]; then
  echo "Refusing to deploy: RPC chain id is $CHAIN, not 84532 (Base Sepolia)" >&2
  exit 1
fi

# Balance check — never prints the key. Address is derived locally by cast.
ADDR="$(cast wallet address --private-key "$QDAY_PRIVATE_KEY" 2>/dev/null || true)"
# The line above may leak via process list; prefer python so the key stays in env.
ADDR="$(python3 - << 'PY'
import os
from eth_account import Account
raw = os.environ["QDAY_PRIVATE_KEY"]
if not raw.startswith("0x"):
    raw = "0x" + raw
print(Account.from_key(raw).address)
PY
)"
BAL="$(cast balance "$ADDR" --rpc-url "$RPC")"
echo "deployer $ADDR"
echo "balance  $BAL wei on Base Sepolia"
if [[ "$BAL" == "0" ]]; then
  echo "No Base Sepolia ETH. Fund the address first (official faucet or official L1 Standard Bridge from Ethereum Sepolia)." >&2
  echo "Official bridge (Ethereum Sepolia): 0xfd0Bf71F60660E2f608ed56e1659C450eB113120" >&2
  exit 2
fi

# --broadcast only. Do not pass --private-key. Script reads QDAY_PRIVATE_KEY.
export BASE_SEPOLIA_RPC="$RPC"
forge script script/DeploySepolia.s.sol --rpc-url "$RPC" --broadcast --slow

echo "wrote deployments/base-sepolia.json"
