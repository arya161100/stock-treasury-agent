"""Research briefs the agent sells. Canned MOCK briefs plus optional live
reference data from the public Coinbase Tokenized Stocks API (mainnet metadata
only — not a price, not advice, not a trade)."""
from __future__ import annotations

import json
import time
import urllib.request
from typing import Any

BRIEFS: dict[str, dict[str, Any]] = {
    "MOCK-AAPL": {
        "ticker": "MOCK-AAPL",
        "title": "MOCK Apple Inc. — testnet research brief",
        "disclaimer": (
            "MOCK / TESTNET ONLY. This is not a security, not a Coinbase tokenized "
            "stock, and not research on Apple Inc. shares. It confers no rights in "
            "any public company. Not investment, legal, or tax advice. Not available "
            "as a product to US users."
        ),
        "summary": (
            "This brief exists so an agent can sell a paid research API on a testnet. "
            "The 'price' used by the mock AMM (10 mock-USDC per MOCK-AAPL) is a fixed "
            "demo rate, not a market."
        ),
        "points": [
            "Official Coinbase tokenized stocks live on Base mainnet (chain 8453) only.",
            "This token is a labeled mock used to demonstrate a permitted vault purchase.",
            "Allocation into this token is gated by the StockTreasuryVault allowlist, caps, and reserve floor.",
        ],
    },
    "MOCK-NVDA": {
        "ticker": "MOCK-NVDA",
        "title": "MOCK NVIDIA Corp. — testnet research brief",
        "disclaimer": (
            "MOCK / TESTNET ONLY. This is not a security, not a Coinbase tokenized "
            "stock, and not research on NVIDIA Corporation shares. It confers no rights "
            "in any public company. Not investment, legal, or tax advice."
        ),
        "summary": (
            "Companion mock to MOCK-AAPL, priced at 20 mock-USDC per token on the mock AMM, "
            "so the vault's allowlist and per-tx cap can be shown on a second name."
        ),
        "points": [
            "Same policy vault, same reserve that the agent cannot invest.",
            "Used in tests to show two allowlisted stocks can be purchased.",
        ],
    },
}


def canned(ticker: str) -> dict[str, Any]:
    key = ticker.upper().strip()
    brief = BRIEFS.get(key)
    if brief is None:
        brief = {
            "ticker": key,
            "title": f"{key} — generic testnet brief",
            "disclaimer": (
                "MOCK / TESTNET ONLY. Not a security. Not investment advice. "
                "No rights in any public company."
            ),
            "summary": (
                "No canned brief for this ticker. The service still did the work of "
                "returning a labeled placeholder so the paid endpoint has a payload."
            ),
            "points": [],
        }
    out = dict(brief)
    out["generatedAt"] = int(time.time())
    out["kind"] = "canned-mock"
    return out


def try_live_reference(ticker: str) -> dict[str, Any] | None:
    """Optional: pull public reference metadata (not a quote) from Coinbase's API."""
    url = "https://api.coinbase.com/v1/tokenized-stocks?page_size=50"
    try:
        req = urllib.request.Request(
            url, headers={"User-Agent": "StockTreasuryAgent/1.0 (testnet demo)", "Accept": "application/json"}
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode())
    except Exception:
        return None
    want = ticker.upper().rstrip("C")  # Coinbase symbols are often 'AAPLc'
    for tok in data.get("tokens") or []:
        sym = (tok.get("symbol") or "").upper()
        if sym == ticker.upper() or sym.rstrip("C") == want:
            return {
                "kind": "coinbase-reference-metadata",
                "note": (
                    "Mainnet reference data only. Not a live price, not executable, "
                    "not available on Base Sepolia. Not investment advice."
                ),
                "symbol": tok.get("symbol"),
                "name": tok.get("name"),
                "contract": tok.get("contract_address"),
                "chain": "base-mainnet-8453",
                "isin": tok.get("isin"),
            }
    return None


def brief_for(ticker: str, include_live: bool = True) -> dict[str, Any]:
    out = canned(ticker)
    if include_live:
        live = try_live_reference(ticker)
        if live:
            out["mainnetReference"] = live
    return out
