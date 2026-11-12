# Video script — StockTreasury Agent (70–80 seconds)

Talking-track + what is on screen. Record against a real `./scripts/demo.sh` run (Anvil) or a Base Sepolia run if funded. Do not invent transaction hashes.

**On-screen lower third throughout:** `TESTNET · MOCK STOCK TOKENS · NOT SECURITIES`

---

**0:00–0:10 — The problem**
- *On screen:* dashboard, empty vault, the four allocation rules.
- *Say:* "If an AI agent earns USDC, it still needs rent money. Track 2.1 of Stocks Maxxing asks for an agent that sells a service, gets paid via x402, and puts only a user-set share of its surplus into stocks — with a reserve it cannot invest."

**0:10–0:22 — The vault**
- *On screen:* `StockTreasuryVault.sol` policy: 50 USDC reserve, 70% allocation, 40 USDC per-tx, 80 USDC daily, allowlisted MOCK-AAPL, owner kill-switch.
- *Say:* "The rules live in a Solidity vault on Base, not in the model's prompt. The agent has a scoped role. It cannot change the policy, and it cannot withdraw the reserve."

**0:22–0:40 — A real payment**
- *On screen:* terminal. `GET /research` returns HTTP 402. Then the agent retries with `X-PAYMENT`. An EIP-3009 `transferWithAuthorization` settles 150 USDC into the vault. The dashboard bar fills: 50 reserve, 70 investable, 30 retained.
- *Say:* "The agent sells a research brief. The buyer pays 150 USDC with x402. The contract fills the 50-dollar reserve first, then marks 70 percent of the surplus investable. The rest is retained cash."

**0:40–0:58 — Operating cost, then a permitted purchase**
- *On screen:* a 10 USDC `payOperatingCost` (retained drops to 20). Then `allocate` 40 USDC. Holdings show 4 MOCK-AAPL. Explorer or Anvil receipt visible. Dashboard bar updates.
- *Say:* "Operating costs come out first, from retained cash. Then the agent buys 40 dollars of MOCK-AAPL through the allowlisted mock AMM. Official tokenized stocks are mainnet-only, so these tokens are clearly labeled mocks."

**0:58–1:15 — The reserve the agent can't invest**
- *On screen:* the agent tries to pay out `balance - reserve + 1`. The call reverts `ReserveBreach`. The rejection log on the dashboard shows a red X. The reserve figure does not move.
- *Say:* "Finally, the agent tries to spend the reserve. The transaction reverts: ReserveBreach. The floor does not move. That's the Show-us: a real payment, a permitted purchase, clear rules, and a reserve the agent cannot invest."

**1:15–1:20 — Close**
- *On screen:* GitHub URL (once published), `@buildonbase`, `#StocksMaxxing`, the TESTNET banner.
- *Say:* "StockTreasury Agent, Track 2.1, testnet only. Thank you."

---

**Recording notes**
- Use the real demo output; pause on the 402, the settle tx, the allocate tx, and the revert.
- If Base Sepolia is funded, prefer those explorer links. If not, say clearly this is a local Anvil run of the same contracts, and that the Foundry tests — including the invariant — are in the repo.
- Total: aim for 75 seconds. Leave 5 seconds of silence at the end for the X player.
