"""Shared RPC + ABI helpers. Never logs a private key."""
from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

from eth_account import Account
from web3 import Web3

ROOT = Path(__file__).resolve().parents[2]
DEPLOYMENTS = ROOT / "deployments"
HERE = Path(__file__).resolve().parent
VAULT_ABI = json.loads((HERE / "abi_vault.json").read_text())
ERC20_ABI = json.loads((HERE / "abi_erc20.json").read_text())


def load_deployment(name: str | None = None) -> dict[str, Any]:
    env = os.environ.get("NETWORK", "")
    sepolia = DEPLOYMENTS / "base-sepolia.json"
    local = DEPLOYMENTS / "local.json"
    if name:
        path = DEPLOYMENTS / name
    elif env == "base-sepolia":
        path = sepolia
    elif local.exists():
        path = local
    else:
        path = sepolia
    if not path.exists():
        raise FileNotFoundError(
            f"deployment file not found: {path} (run scripts/demo.sh or DeploySepolia first)"
        )
    return json.loads(path.read_text())


def connect(rpc: str | None = None, chain_id: int | None = None) -> Web3:
    rpc = rpc or os.environ.get("RPC_URL") or os.environ.get("BASE_SEPOLIA_RPC") or "http://127.0.0.1:8545"
    w3 = Web3(Web3.HTTPProvider(rpc, request_kwargs={"timeout": 30}))
    if not w3.is_connected():
        raise ConnectionError(f"cannot connect to RPC {rpc}")
    if chain_id is not None and w3.eth.chain_id != chain_id:
        raise RuntimeError(f"refusing chain id {w3.eth.chain_id}, expected {chain_id}")
    return w3


def account_from_env(env_name: str = "LOCAL_PRIVATE_KEY"):
    raw = os.environ.get(env_name) or os.environ.get("ANVIL_PRIVATE_KEY")
    if not raw:
        # Well-known Anvil account #0. Public test key, not a secret.
        raw = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
    if not raw.startswith("0x"):
        raw = "0x" + raw
    return Account.from_key(raw)


def send(w3: Web3, acct, tx: dict) -> str:
    tx = dict(tx)
    tx.setdefault("from", acct.address)
    tx.setdefault("nonce", w3.eth.get_transaction_count(acct.address))
    tx.setdefault("chainId", w3.eth.chain_id)
    if "gasPrice" not in tx and "maxFeePerGas" not in tx:
        try:
            block = w3.eth.get_block("latest")
            base = block.get("baseFeePerGas") or 0
            tip = w3.eth.max_priority_fee
            tx["maxPriorityFeePerGas"] = tip
            tx["maxFeePerGas"] = base * 2 + tip
        except Exception:
            tx["gasPrice"] = w3.eth.gas_price
    if "gas" not in tx:
        tx["gas"] = int(w3.eth.estimate_gas(tx) * 1.2)
    signed = acct.sign_transaction(tx)
    raw = getattr(signed, "raw_transaction", None) or getattr(signed, "rawTransaction")
    h = w3.eth.send_raw_transaction(raw)
    receipt = w3.eth.wait_for_transaction_receipt(h)
    hx = w3.to_hex(h)
    if receipt.status != 1:
        raise RuntimeError(f"tx failed: {hx} (status=0)")
    return hx


_ERROR_SELECTORS = {
    "0x5bb39a97": "ReserveBreach",
    # filled at import time if we also match by name
}

def decode_revert(err: Exception) -> str:
    msg = str(err)
    for label in (
        "ReserveBreach",
        "ExceedsInvestable",
        "PerTxCapExceeded",
        "DailyCapExceeded",
        "StockNotAllowed",
        "Paused",
        "NotAgent",
        "CostRecipientNotAllowed",
        "ZeroAmount",
        "PolicyNotSet",
        "AuthorizationAlreadyUsed",
        "InvalidSignature",
        "AuthorizationExpired",
    ):
        if label in msg:
            return label
    # Custom-error selector (first 4 bytes of keccak(signature)).
    selectors = {
        "5bb39a97": "ReserveBreach",
        "0x5bb39a97": "ReserveBreach",
    }
    try:
        from eth_hash.auto import keccak as _keccak
        for sig, name in (
            ("ReserveBreach(uint256,uint256,uint256)", "ReserveBreach"),
            ("ExceedsInvestable(uint256,uint256)", "ExceedsInvestable"),
            ("PerTxCapExceeded(uint256,uint256)", "PerTxCapExceeded"),
            ("DailyCapExceeded(uint256,uint256,uint256)", "DailyCapExceeded"),
            ("StockNotAllowed(address)", "StockNotAllowed"),
            ("Paused()", "Paused"),
            ("NotAgent()", "NotAgent"),
            ("CostRecipientNotAllowed(address)", "CostRecipientNotAllowed"),
        ):
            selectors[_keccak(sig.encode()).hex()[:8]] = name
    except Exception:
        pass
    low = msg.lower()
    for sel, name in selectors.items():
        if sel.lower() in low:
            return name
    return msg[:240]


def preview_dict(p) -> dict[str, Any]:
    def dec6(x) -> str:
        return f"{int(x) / 1e6:.6f}"

    names = (
        "usdc", "owner", "agent", "router", "allocationBps",
        "operatingReserveTarget", "perTxCap", "dailyCap", "dailyUsed",
        "dailyWindow", "paused", "policySet", "usdcBalance", "investable",
        "reservedEffective", "retained", "lastAccounted",
    )
    if isinstance(p, (list, tuple)):
        vals = list(p)
        # web3 may wrap the struct as a 1-tuple
        if len(vals) == 1 and isinstance(vals[0], (list, tuple)):
            vals = list(vals[0])
        data = dict(zip(names, vals))
    elif hasattr(p, "_asdict"):
        data = dict(p._asdict())
    else:
        data = {n: getattr(p, n) for n in names}

    bps = int(data["allocationBps"])
    return {
        "usdc": data["usdc"],
        "owner": data["owner"],
        "agent": data["agent"],
        "router": data["router"],
        "allocationBps": bps,
        "allocationPct": bps / 100,
        "operatingReserveTarget": dec6(data["operatingReserveTarget"]),
        "operatingReserveTargetRaw": str(int(data["operatingReserveTarget"])),
        "perTxCap": dec6(data["perTxCap"]),
        "dailyCap": dec6(data["dailyCap"]),
        "dailyUsed": dec6(data["dailyUsed"]),
        "paused": bool(data["paused"]),
        "policySet": bool(data["policySet"]),
        "usdcBalance": dec6(data["usdcBalance"]),
        "investable": dec6(data["investable"]),
        "reservedEffective": dec6(data["reservedEffective"]),
        "retained": dec6(data["retained"]),
        "lastAccounted": dec6(data["lastAccounted"]),
    }
