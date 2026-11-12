# Honest scope notes

## What this project is

A Track 2.1 ("Agents that earn their stock treasury") prototype for Base Stocks Maxxing. It demonstrates, on a testnet or a local chain:

- A real USDC payment (x402 exact scheme, EIP-3009 `transferWithAuthorization`) landing in a vault.
- Clear on-chain allocation rules: reserve first, then a user-set percentage of surplus, then retained cash.
- A permitted purchase of an allowlisted stock token through an allowlisted router.
- A reserve the agent cannot invest, proven by a `ReserveBreach` revert and by a 256-run Foundry invariant.

## What this project is not

- Not a mainnet product and not deployed on Base mainnet (8453).
- Not a Coinbase tokenized stock, not a security, and not a claim on any public company.
- Not a securities exchange, broker, or investment adviser.
- Not available as a trading product for US users (or anyone else).
- Not affiliated with Apple, NVIDIA, or any issuer whose name appears only in a MOCK label.
- Not using the Binance Agentic Wallet or any mainnet wallet.

## Why mocks

On 12 Nov 2026, `GET https://api.coinbase.com/v1/tokenized-stocks/chains` returned a single chain, Base mainnet (`8453`). The Stocks Maxxing Quest Page HTML that was fetched did not list Base Sepolia stock-token addresses. Official rules allow testnet submissions and say they will not be judged less favorably.

So the stock tokens and the AMM are mocks, labeled in the token `name`, a public `DISCLAIMER` string, the dashboard banner, and this file. If official Sepolia stock tokens appear later, `setStockAllowed` and `setRouter` can point the same vault at them without changing the policy engine.

## x402 libraries

The payment flow follows the Coinbase x402 v1 `exact` shape (`PaymentRequirements`, `X-PAYMENT`, EIP-3009 authorization) documented in Base's "Call a Paid Service" guide and implemented here in Python (`tools/lib/x402.py`) so the demo has no npm install step. The public facilitator at `https://x402.org/facilitator` is for testnets; this repo settles locally by submitting `transferWithAuthorization`, which is the same on-chain action a facilitator would submit.

## Funds and keys

- Local demo: Anvil account #0, a well-known public test key.
- Testnet: Arya's designated testnet wallet `0xA514D7E29abaEb5a4bc4932B0F488A4c20f69D22`, via `QDAY_PRIVATE_KEY`. The key is never printed, never committed, and never passed on a process command line in the deploy path (Forge reads it from the environment).
