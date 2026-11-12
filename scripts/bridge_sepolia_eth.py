#!/usr/bin/env python3
"""Official Ethereum-Sepolia -> Base-Sepolia ETH bridge.

Uses the L1StandardBridge published in Base's own contract list:
  https://docs.base.org/base-chain/network-information/base-contracts.md
  L1StandardBridge (Ethereum Sepolia) = 0xfd0Bf71F60660E2f608ed56e1659C450eB113120

Refuses any chain other than 11155111. Never prints the private key.
Default amount is 0.2 ETH. Override with BRIDGE_ETH_AMOUNT (ether units).
"""
from __future__ import annotations

import os
import sys
import time

from eth_account import Account
from web3 import Web3

ETH_SEPOLIA = 11155111
BRIDGE = Web3.to_checksum_address("0xfd0Bf71F60660E2f608ed56e1659C450eB113120")
# depositETH(uint32 _minGasLimit, bytes _extraData) payable
ABI = [
    {
        "type": "function",
        "name": "depositETH",
        "stateMutability": "payable",
        "inputs": [
            {"name": "_minGasLimit", "type": "uint32"},
            {"name": "_extraData", "type": "bytes"},
        ],
        "outputs": [],
    },
    {
        "type": "function",
        "name": "bridgeETH",
        "stateMutability": "payable",
        "inputs": [
            {"name": "_minGasLimit", "type": "uint32"},
            {"name": "_extraData", "type": "bytes"},
        ],
        "outputs": [],
    },
]


def main() -> int:
    raw = os.environ.get("QDAY_PRIVATE_KEY")
    if not raw:
        print("QDAY_PRIVATE_KEY is not set", file=sys.stderr)
        return 1
    if not raw.startswith("0x"):
        raw = "0x" + raw
    acct = Account.from_key(raw)

    rpc = os.environ.get("ETH_SEPOLIA_RPC") or "https://ethereum-sepolia-rpc.publicnode.com"
    w3 = Web3(Web3.HTTPProvider(rpc, request_kwargs={"timeout": 30}))
    if not w3.is_connected():
        print(f"cannot reach Ethereum Sepolia RPC {rpc}", file=sys.stderr)
        return 1
    if w3.eth.chain_id != ETH_SEPOLIA:
        print(f"Refusing: chain id {w3.eth.chain_id} is not Ethereum Sepolia (11155111)", file=sys.stderr)
        return 1

    code = w3.eth.get_code(BRIDGE)
    if not code or code == b"\x00" or code == b"":
        print(f"Refusing: official bridge {BRIDGE} has no code on this chain", file=sys.stderr)
        return 1

    amount = Web3.to_wei(os.environ.get("BRIDGE_ETH_AMOUNT", "0.2"), "ether")
    bal = w3.eth.get_balance(acct.address)
    print(f"from     {acct.address}")
    print(f"bridge   {BRIDGE}")
    print(f"chain    {w3.eth.chain_id} (Ethereum Sepolia)")
    print(f"balance  {Web3.from_wei(bal, 'ether')} ETH")
    print(f"deposit  {Web3.from_wei(amount, 'ether')} ETH")
    if bal < amount + Web3.to_wei(0.005, "ether"):
        print("insufficient Ethereum Sepolia ETH (need amount + gas)", file=sys.stderr)
        return 1

    contract = w3.eth.contract(address=BRIDGE, abi=ABI)
    # Prefer depositETH; fall back to bridgeETH if estimate fails.
    fn = contract.functions.depositETH(200_000, b"")
    try:
        fn.estimate_gas({"from": acct.address, "value": amount})
    except Exception as e:
        print(f"depositETH estimate failed ({e}); trying bridgeETH")
        fn = contract.functions.bridgeETH(200_000, b"")

    tx = fn.build_transaction(
        {
            "from": acct.address,
            "value": amount,
            "nonce": w3.eth.get_transaction_count(acct.address),
            "chainId": ETH_SEPOLIA,
        }
    )
    try:
        block = w3.eth.get_block("latest")
        base = block.get("baseFeePerGas") or 0
        tip = w3.eth.max_priority_fee
        tx["maxPriorityFeePerGas"] = tip
        tx["maxFeePerGas"] = base * 2 + tip
    except Exception:
        tx["gasPrice"] = w3.eth.gas_price
    tx["gas"] = int(w3.eth.estimate_gas(tx) * 1.2)
    signed = acct.sign_transaction(tx)
    raw_tx = getattr(signed, "raw_transaction", None) or signed.rawTransaction
    h = w3.eth.send_raw_transaction(raw_tx)
    hx = w3.to_hex(h)
    print(f"submitted {hx}")
    print(f"explorer  https://sepolia.etherscan.io/tx/{hx}")
    receipt = w3.eth.wait_for_transaction_receipt(h, timeout=180)
    if receipt.status != 1:
        print("bridge tx failed (status=0)", file=sys.stderr)
        return 1
    print(f"confirmed in block {receipt.blockNumber}")
    print("L2 credit on Base Sepolia usually arrives within a few minutes.")
    print("Check https://sepolia.basescan.org/address/%s" % acct.address)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:
        print(f"bridge failed: {type(e).__name__}: {e}", file=sys.stderr)
        sys.exit(1)
