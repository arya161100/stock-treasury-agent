"""x402 exact-scheme helpers for Base Sepolia / Anvil.

The seller (research API) returns HTTP 402 with PaymentRequirements.
The buyer signs an EIP-3009 TransferWithAuthorization paying the vault.
A local facilitator (or the service itself) submits transferWithAuthorization
so USDC actually moves on-chain — a real payment, not a stub.

Compatible with the x402 v1 payment-payload shape used by Coinbase x402
libraries. The public facilitator at https://x402.org/facilitator is for
testnets; this module can also settle locally without it.

Never logs a private key.
"""
from __future__ import annotations

import os
import secrets
import time
from typing import Any

from eth_account import Account
from eth_account.messages import encode_typed_data
from web3 import Web3

from .chain import ERC20_ABI


def payment_requirements(
    *,
    pay_to: str,
    asset: str,
    amount: int,
    resource: str,
    network: str,
    asset_name: str,
    asset_version: str = "2",
    description: str = "Tokenized-stock research brief (testnet demo)",
) -> dict[str, Any]:
    return {
        "x402Version": 1,
        "error": "X-PAYMENT header is required",
        "accepts": [
            {
                "scheme": "exact",
                "network": network,
                "maxAmountRequired": str(amount),
                "resource": resource,
                "description": description,
                "mimeType": "application/json",
                "payTo": Web3.to_checksum_address(pay_to),
                "maxTimeoutSeconds": 300,
                "asset": Web3.to_checksum_address(asset),
                "extra": {"name": asset_name, "version": asset_version},
            }
        ],
    }


def sign_transfer_authorization(
    acct,
    *,
    token_name: str,
    token_version: str,
    chain_id: int,
    token_address: str,
    to: str,
    value: int,
    valid_after: int = 0,
    valid_before: int | None = None,
    nonce: bytes | None = None,
) -> dict[str, Any]:
    if valid_before is None:
        valid_before = int(time.time()) + 300
    if nonce is None:
        nonce = secrets.token_bytes(32)
    if isinstance(nonce, str):
        nonce_hex = nonce if nonce.startswith("0x") else "0x" + nonce
        nonce_bytes = bytes.fromhex(nonce_hex[2:])
    else:
        nonce_bytes = nonce
        nonce_hex = "0x" + nonce_bytes.hex()

    typed = {
        "types": {
            "EIP712Domain": [
                {"name": "name", "type": "string"},
                {"name": "version", "type": "string"},
                {"name": "chainId", "type": "uint256"},
                {"name": "verifyingContract", "type": "address"},
            ],
            "TransferWithAuthorization": [
                {"name": "from", "type": "address"},
                {"name": "to", "type": "address"},
                {"name": "value", "type": "uint256"},
                {"name": "validAfter", "type": "uint256"},
                {"name": "validBefore", "type": "uint256"},
                {"name": "nonce", "type": "bytes32"},
            ],
        },
        "primaryType": "TransferWithAuthorization",
        "domain": {
            "name": token_name,
            "version": token_version,
            "chainId": chain_id,
            "verifyingContract": Web3.to_checksum_address(token_address),
        },
        "message": {
            "from": Web3.to_checksum_address(acct.address),
            "to": Web3.to_checksum_address(to),
            "value": int(value),
            "validAfter": int(valid_after),
            "validBefore": int(valid_before),
            "nonce": nonce_bytes,
        },
    }
    signed = acct.sign_typed_data(full_message=typed)
    v = signed.v
    r = "0x" + signed.r.to_bytes(32, "big").hex()
    s = "0x" + signed.s.to_bytes(32, "big").hex()
    sig = signed.signature.hex()
    if not sig.startswith("0x"):
        sig = "0x" + sig
    return {
        "from": Web3.to_checksum_address(acct.address),
        "to": Web3.to_checksum_address(to),
        "value": str(int(value)),
        "validAfter": str(int(valid_after)),
        "validBefore": str(int(valid_before)),
        "nonce": nonce_hex,
        "v": v,
        "r": r,
        "s": s,
        "signature": sig,
    }


def payment_header(auth: dict[str, Any], network: str) -> dict[str, Any]:
    return {
        "x402Version": 1,
        "scheme": "exact",
        "network": network,
        "payload": {
            "signature": auth["signature"],
            "authorization": {
                "from": auth["from"],
                "to": auth["to"],
                "value": auth["value"],
                "validAfter": auth["validAfter"],
                "validBefore": auth["validBefore"],
                "nonce": auth["nonce"],
            },
        },
    }


def settle_transfer_with_authorization(w3: Web3, settler, usdc_addr: str, auth: dict[str, Any]) -> str:
    """Submit EIP-3009 transferWithAuthorization. `settler` pays gas, not USDC."""
    from .chain import send

    usdc = w3.eth.contract(address=Web3.to_checksum_address(usdc_addr), abi=__import__("json").loads(
        __import__("pathlib").Path(__file__).with_name("abi_erc20.json").read_text()
    ))
    fn = usdc.functions.transferWithAuthorization(
        Web3.to_checksum_address(auth["from"]),
        Web3.to_checksum_address(auth["to"]),
        int(auth["value"]),
        int(auth["validAfter"]),
        int(auth["validBefore"]),
        auth["nonce"] if isinstance(auth["nonce"], (bytes, bytearray)) else bytes.fromhex(auth["nonce"][2:]),
        int(auth["v"]),
        auth["r"],
        auth["s"],
    )
    tx = fn.build_transaction({"from": settler.address})
    return send(w3, settler, tx)
