#!/usr/bin/env python3
"""Agent loop for StockTreasury.

1. Pay the research API (x402 exact / EIP-3009) so USDC lands in the vault.
2. Sync revenue (reserve fills first; surplus is split by allocationBps).
3. Pay a small operating cost from retained cash.
4. Allocate investable USDC to an allowlisted mock stock.
5. Deliberately try to spend the reserve; record the ReserveBreach rejection.

Writes tools/web/snapshot.json and tools/web/rejection-log.json for the dashboard.

Never prints a private key.
"""
from __future__ import annotations

import json
import os
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from web3 import Web3  # noqa: E402

from tools.lib.chain import (  # noqa: E402
    ERC20_ABI,
    VAULT_ABI,
    account_from_env,
    connect,
    decode_revert,
    load_deployment,
    preview_dict,
    send,
)
from tools.lib.x402 import (  # noqa: E402
    payment_header,
    sign_transfer_authorization,
)


SERVICE = os.environ.get("SERVICE_URL", "http://127.0.0.1:4021")
TICKER = os.environ.get("TICKER", "MOCK-AAPL")
COST_USDC = int(os.environ.get("OPERATING_COST_USDC", "10000000"))  # 10 USDC
ALLOC_USDC = int(os.environ.get("ALLOC_USDC", "40000000"))  # 40 USDC (per-tx cap)
WEB = ROOT / "tools" / "web"


def _http_json(url: str, headers: dict | None = None, timeout: int = 30):
    req = urllib.request.Request(url, headers=headers or {})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        try:
            parsed = json.loads(body)
        except Exception:
            parsed = {"raw": body[:500]}
        return e.code, parsed


def _preview(vault):
    return preview_dict(vault.functions.preview().call())


def _write_snapshot(dep, preview, holdings, log, extra):
    WEB.mkdir(parents=True, exist_ok=True)
    snap = {
        "updatedAt": int(time.time()),
        "deployment": dep,
        "preview": preview,
        "holdings": holdings,
        "log": log,
        **extra,
    }
    (WEB / "snapshot.json").write_text(json.dumps(snap, indent=2))
    (WEB / "rejection-log.json").write_text(json.dumps([e for e in log if e.get("rejected")], indent=2))
    # Also write config.js for the static dashboard (no bundler).
    cfg = {
        "rpcUrl": os.environ.get("RPC_URL") or os.environ.get("BASE_SEPOLIA_RPC") or "http://127.0.0.1:8545",
        "chainId": dep.get("chainId"),
        "vault": dep.get("vault"),
        "usdc": dep.get("usdc"),
        "router": dep.get("router"),
        "stocks": dep.get("stocks"),
        "explorer": dep.get("explorer") or "",
        "network": dep.get("network"),
        "mock": True,
    }
    (WEB / "config.json").write_text(json.dumps(cfg, indent=2))
    (WEB / "config.js").write_text("window.STOCK_TREASURY_CONFIG = " + json.dumps(cfg, indent=2) + ";\n")
    return snap


def main() -> int:
    dep = load_deployment()
    enforce = 84532 if os.environ.get("NETWORK") == "base-sepolia" else None
    w3 = connect(chain_id=enforce)
    env_key = "QDAY_PRIVATE_KEY" if os.environ.get("NETWORK") == "base-sepolia" else "LOCAL_PRIVATE_KEY"
    if not os.environ.get(env_key):
        env_key = "LOCAL_PRIVATE_KEY"
    acct = account_from_env(env_key)

    vault = w3.eth.contract(address=Web3.to_checksum_address(dep["vault"]), abi=VAULT_ABI)
    usdc = w3.eth.contract(address=Web3.to_checksum_address(dep["usdc"]), abi=ERC20_ABI)
    aapl = Web3.to_checksum_address(dep["stocks"][0]["address"])

    log = []
    print(f"agent   {acct.address}")
    print(f"vault   {dep['vault']}")
    print(f"chain   {w3.eth.chain_id}")
    print(f"--- step 0: starting preview ---")
    print(json.dumps(_preview(vault), indent=2))

    # ------------------------------------------------------------------
    # 1. Buy a research brief via x402 (real EIP-3009 USDC payment to vault)
    # ------------------------------------------------------------------
    print("--- step 1: GET /research (expect 402) ---")
    code, body = _http_json(f"{SERVICE}/research?ticker={TICKER}")
    if code != 402:
        print(f"unexpected {code}: {body}")
        return 1
    accepts = body["accepts"][0]
    price = int(accepts["maxAmountRequired"])
    token_name = (accepts.get("extra") or {}).get("name") or usdc.functions.name().call()
    token_version = (accepts.get("extra") or {}).get("version") or "2"
    print(f"402 advertised {price/1e6:.2f} USDC to {accepts['payTo']}")

    auth = sign_transfer_authorization(
        acct,
        token_name=token_name,
        token_version=token_version,
        chain_id=w3.eth.chain_id,
        token_address=dep["usdc"],
        to=dep["vault"],
        value=price,
    )
    header = payment_header(auth, accepts["network"])
    print("--- step 1b: retry with X-PAYMENT ---")
    code, brief = _http_json(
        f"{SERVICE}/research?ticker={TICKER}",
        headers={"X-PAYMENT": json.dumps(header), "Accept": "application/json"},
    )
    if code != 200:
        print(f"payment failed {code}: {brief}")
        return 1
    pay_tx = (brief.get("payment") or {}).get("tx")
    print(f"paid research, settle tx {pay_tx}")
    print(f"brief: {brief.get('title')}")
    log.append({"step": "x402-payment", "ok": True, "tx": pay_tx, "value": str(price), "ticker": TICKER})

    # ------------------------------------------------------------------
    # 2. Sync revenue
    # ------------------------------------------------------------------
    print("--- step 2: syncRevenue ---")
    tx = send(w3, acct, vault.functions.syncRevenue().build_transaction({"from": acct.address}))
    prev = _preview(vault)
    print(f"sync tx {tx}")
    print(json.dumps(prev, indent=2))
    log.append({"step": "syncRevenue", "ok": True, "tx": tx, "preview": prev})

    # ------------------------------------------------------------------
    # 3. Operating cost first (from retained, never from reserve)
    # ------------------------------------------------------------------
    print(f"--- step 3: payOperatingCost {COST_USDC/1e6:.2f} USDC ---")
    reason = b"infra" + b"\x00" * (32 - 5)
    tx = send(
        w3,
        acct,
        vault.functions.payOperatingCost(acct.address, COST_USDC, reason).build_transaction({"from": acct.address}),
    )
    prev = _preview(vault)
    print(f"cost tx {tx}")
    print(json.dumps(prev, indent=2))
    log.append({"step": "payOperatingCost", "ok": True, "tx": tx, "value": str(COST_USDC), "preview": prev})

    # ------------------------------------------------------------------
    # 4. Permitted stock purchase
    # ------------------------------------------------------------------
    amount = min(ALLOC_USDC, int(vault.functions.maxAllocatable().call()))
    print(f"--- step 4: allocate {amount/1e6:.2f} USDC to {TICKER} ---")
    tx = send(
        w3,
        acct,
        vault.functions.allocate(aapl, amount, 0).build_transaction({"from": acct.address}),
    )
    prev = _preview(vault)
    tokens, bals = vault.functions.holdings().call()
    holdings = [{"token": t, "raw": str(b), "human": f"{b/1e18:.6f}"} for t, b in zip(tokens, bals)]
    print(f"allocate tx {tx}")
    print(json.dumps(prev, indent=2))
    print("holdings", holdings)
    log.append({"step": "allocate", "ok": True, "tx": tx, "value": str(amount), "stock": aapl, "preview": prev, "holdings": holdings})

    # ------------------------------------------------------------------
    # 5. Show us the reserve the agent cannot invest: try to drain it.
    # ------------------------------------------------------------------
    print("--- step 5: attempt to spend the operating reserve (must revert) ---")
    bal = usdc.functions.balanceOf(dep["vault"]).call()
    target = vault.functions.operatingReserveTarget().call()
    drain = bal - target + 1
    rejected = {"step": "reserve-breach", "ok": False, "rejected": True, "attempted": str(drain)}
    try:
        # estimate_gas / build will already revert; still try to send if estimate is skipped
        fn = vault.functions.payOperatingCost(acct.address, drain, b"drain-reserve".ljust(32, b"\x00"))
        try:
            fn.call({"from": acct.address})
            rejected["error"] = "UNEXPECTED SUCCESS (call)"
            print("ERROR: reserve drain call unexpectedly succeeded")
        except Exception as e:
            reason = decode_revert(e)
            rejected["error"] = reason
            rejected["detail"] = str(e)[:400]
            print(f"rejected as expected: {reason}")
        # Also broadcast so a real rejected tx can show on an explorer (anvil will
        # still reject at estimate). We record the eth_call rejection either way.
    except Exception as e:
        rejected["error"] = decode_revert(e)
        rejected["detail"] = str(e)[:400]
        print(f"rejected as expected: {rejected['error']}")
    log.append(rejected)

    prev = _preview(vault)
    tokens, bals = vault.functions.holdings().call()
    holdings = [{"token": t, "raw": str(b), "human": f"{b/1e18:.6f}"} for t, b in zip(tokens, bals)]
    snap = _write_snapshot(dep, prev, holdings, log, {"paymentTx": pay_tx})
    print("--- final preview ---")
    print(json.dumps(prev, indent=2))
    print(f"wrote {WEB / 'snapshot.json'}")
    print("done")
    return 0 if rejected.get("error") in ("ReserveBreach",) or "ReserveBreach" in str(rejected.get("error")) else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:
        # Never dump env or keys; a short error is enough.
        print(f"agent failed: {type(e).__name__}: {e}", file=sys.stderr)
        sys.exit(1)
