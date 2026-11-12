#!/usr/bin/env python3
"""x402-paid research API.

GET /research?ticker=MOCK-AAPL
  - Without X-PAYMENT: HTTP 402 + PaymentRequirements (payTo = the vault).
  - With a valid X-PAYMENT: settle EIP-3009 USDC to the vault, then return the brief.

This is the "sells a service, gets paid in USDC via x402" half of Track 2.1.

Usage:
  NETWORK=anvil python3 tools/service/server.py
  NETWORK=base-sepolia RPC_URL=https://sepolia.base.org python3 tools/service/server.py
"""
from __future__ import annotations

import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from tools.lib.chain import ERC20_ABI, account_from_env, connect, load_deployment  # noqa: E402
from tools.lib.research import brief_for  # noqa: E402
from tools.lib.x402 import payment_requirements, settle_transfer_with_authorization  # noqa: E402
from web3 import Web3  # noqa: E402

HOST = os.environ.get("HOST", "127.0.0.1")
PORT = int(os.environ.get("PORT", "4021"))
PRICE = int(os.environ.get("RESEARCH_PRICE_USDC", "150000000"))


def _setup():
    dep = load_deployment()
    enforce = 84532 if os.environ.get("NETWORK") == "base-sepolia" else None
    w3 = connect(chain_id=enforce)
    settler_env = "QDAY_PRIVATE_KEY" if os.environ.get("NETWORK") == "base-sepolia" else "LOCAL_PRIVATE_KEY"
    if not os.environ.get(settler_env):
        settler_env = "LOCAL_PRIVATE_KEY"
    settler = account_from_env(settler_env)
    usdc = w3.eth.contract(address=Web3.to_checksum_address(dep["usdc"]), abi=ERC20_ABI)
    try:
        token_name = usdc.functions.name().call()
    except Exception:
        token_name = "USD Coin"
    try:
        token_version = usdc.functions.version().call()
    except Exception:
        token_version = "2"
    network = "base-sepolia" if w3.eth.chain_id == 84532 else f"eip155:{w3.eth.chain_id}"
    return {
        "dep": dep,
        "w3": w3,
        "settler": settler,
        "usdc": usdc,
        "token_name": token_name,
        "token_version": token_version,
        "network": network,
        "vault": Web3.to_checksum_address(dep["vault"]),
        "asset": Web3.to_checksum_address(dep["usdc"]),
        "settlements": [],
    }


CTX = None


class Handler(BaseHTTPRequestHandler):
    server_version = "StockTreasuryResearch/1.0"

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    def _json(self, code: int, body: dict, extra_headers: dict | None = None):
        raw = json.dumps(body, indent=2).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "X-PAYMENT, Content-Type")
        if extra_headers:
            for k, v in extra_headers.items():
                self.send_header(k, v)
        self.end_headers()
        self.wfile.write(raw)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "X-PAYMENT, Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
        self.end_headers()

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        qs = parse_qs(parsed.query)
        if path in ("/health", "/"):
            self._json(200, {
                "ok": True,
                "service": "StockTreasury research API",
                "network": CTX["network"],
                "chainId": CTX["w3"].eth.chain_id,
                "payTo": CTX["vault"],
                "asset": CTX["asset"],
                "price": str(PRICE),
                "disclaimer": "TESTNET DEMO. Mock briefs. Not investment advice.",
            })
            return
        if path in ("/.well-known/x402", "/price"):
            req = payment_requirements(
                pay_to=CTX["vault"],
                asset=CTX["asset"],
                amount=PRICE,
                resource=f"http://{HOST}:{PORT}/research",
                network=CTX["network"],
                asset_name=CTX["token_name"],
                asset_version=CTX["token_version"],
            )
            self._json(200, req)
            return
        if path != "/research":
            self._json(404, {"error": "not found"})
            return

        ticker = (qs.get("ticker") or ["MOCK-AAPL"])[0]
        payment_raw = self.headers.get("X-PAYMENT") or self.headers.get("PAYMENT-SIGNATURE")
        if not payment_raw:
            req = payment_requirements(
                pay_to=CTX["vault"],
                asset=CTX["asset"],
                amount=PRICE,
                resource=f"http://{HOST}:{PORT}/research?ticker={ticker}",
                network=CTX["network"],
                asset_name=CTX["token_name"],
                asset_version=CTX["token_version"],
            )
            self._json(402, req, extra_headers={"PAYMENT-REQUIRED": "true"})
            return

        try:
            payment = json.loads(payment_raw)
        except Exception:
            self._json(400, {"error": "X-PAYMENT is not JSON"})
            return

        try:
            auth = _extract_auth(payment)
            _validate_auth(auth, CTX, PRICE)
            txh = settle_transfer_with_authorization(CTX["w3"], CTX["settler"], CTX["asset"], auth)
        except Exception as e:
            self._json(402, {"error": "payment settlement failed", "detail": str(e)[:300]})
            return

        brief = brief_for(ticker, include_live=os.environ.get("NETWORK") == "base-sepolia")
        brief["payment"] = {
            "tx": txh,
            "from": auth["from"],
            "to": auth["to"],
            "value": auth["value"],
            "asset": CTX["asset"],
            "scheme": "exact",
            "settled": True,
        }
        CTX["settlements"].append({"tx": txh, "ticker": ticker, "value": auth["value"]})
        self._json(200, brief, extra_headers={"PAYMENT-RESPONSE": json.dumps({"tx": txh, "success": True})})


def _extract_auth(payment: dict) -> dict:
    payload = payment.get("payload") or payment
    auth = payload.get("authorization") or payload
    sig = payload.get("signature") or payment.get("signature") or ""
    if sig.startswith("0x") and len(sig) == 132:
        raw = bytes.fromhex(sig[2:])
        r = "0x" + raw[0:32].hex()
        s = "0x" + raw[32:64].hex()
        v = raw[64]
        if v in (0, 1):
            v += 27
    else:
        r = auth.get("r") or payload.get("r")
        s = auth.get("s") or payload.get("s")
        v = int(auth.get("v") or payload.get("v") or 0)
    return {
        "from": auth["from"],
        "to": auth["to"],
        "value": str(auth["value"]),
        "validAfter": str(auth.get("validAfter") or 0),
        "validBefore": str(auth["validBefore"]),
        "nonce": auth["nonce"],
        "v": v,
        "r": r,
        "s": s,
        "signature": sig,
    }


def _validate_auth(auth: dict, ctx: dict, price: int) -> None:
    if Web3.to_checksum_address(auth["to"]) != ctx["vault"]:
        raise ValueError("payTo must be the vault")
    if int(auth["value"]) < price:
        raise ValueError("payment below advertised price")


def main():
    global CTX
    CTX = _setup()
    print(f"StockTreasury research API on http://{HOST}:{PORT}", flush=True)
    print(f"  chain   {CTX['w3'].eth.chain_id}", flush=True)
    print(f"  payTo   {CTX['vault']}", flush=True)
    print(f"  asset   {CTX['asset']}", flush=True)
    print(f"  price   {PRICE} ({PRICE/1e6:.2f} USDC)", flush=True)
    print(f"  settler {CTX['settler'].address}", flush=True)
    httpd = ThreadingHTTPServer((HOST, PORT), Handler)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("shutting down", flush=True)
        httpd.server_close()


if __name__ == "__main__":
    main()
