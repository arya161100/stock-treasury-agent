# Base Stocks Maxxing — research notes

Fetched 12 Nov 2026 (WIB). Sources are first-party pages unless noted.
Track-section accordions on the Quest Page are client-collapsed in the static HTML, so some Track 2.1 prize-line and judging-criteria wording was **not** present in the raw document. Those gaps are marked below. Do not treat a gap as a rule.

## Official pages

- Quest Page: https://www.base.org/stocksmaxxing
- Official Rules: https://www.base.org/stocksmaxxing/rules
- Submission form (linked from the Quest Page): https://docs.google.com/forms/d/1zotYvkeAtDjR2MKk3qNxyNIAfJ_IPQtzTtjNhOAF8js/viewform
- Tokenized Stocks API docs: https://docs.base.org/sdks/tokenized-stocks/overview
- List / integrate tokenized stocks: https://docs.base.org/build-on-base/integrate-defi/list-tokenized-stocks
- Base Sepolia faucets: https://docs.base.org/base-chain/network-information/network-faucets.md
- Official L1/L2 contract addresses: https://docs.base.org/base-chain/network-information/base-contracts.md
- x402 "call a paid service" (Base Sepolia USDC): https://docs.base.org/build-on-base/accept-payments/call-a-paid-service.md

## Quest period and prizes

- Skill-based contest. No purchase necessary. Testnet submissions are explicitly allowed and "will not be judged less favorably because they were built on testnet" (Official Rules §5).
- Period: **5 Nov 2026 – 5 Dec 2026, 11:59 PM UTC** (Quest Page FAQ: "Share a Loom demo on X and tag @buildonbase, then complete the submission form by 11:59 PM UTC on December 5, 2026." In Asia/Jakarta that is **6 Dec 2026, 06:59 WIB**).
- "$100,000+" breakdown (Quest Page FAQ):
  - **$50,000** in Base-track prizes
  - **$48,000** across partner prizes (separate mechanisms and terms)
  - **$6,000** community-voted build-in-public award
- Prize currency, unless the Quest Page says otherwise: USD amounts paid in **USDC on Base** (Official Rules §10). Individual per-track prize tables live in each Track Section accordion and were **not visible** in the static HTML (accordions `aria-expanded="false"`).
- Dates, reward amounts, partner participation, and judging criteria may change. Coinbase and Base may modify, suspend, or cancel the campaign.

## How to enter (Official Rules §5 + Quest Page FAQ)

1. Publish a public X post with a **video demo** (e.g. Loom) explaining how the project works, tagging **@buildonbase**.
2. Complete the official Submission Form, including the X-post link and the Track(s) entered.
3. Meet any extra requirements in the Track Section.
4. "Didn't register? You can still submit."
5. One Submission per Track per Entrant/Team unless the Quest Page says otherwise. A project may enter more than one Track only if the Quest Page allows it, and may win a prize in only one Track unless the page says otherwise.
6. Build-in-public award: share the journey on X, tag @buildonbase; community votes; winner gets $6,000.

## Eligibility (Official Rules §4 + Quest Page FAQ)

- Individuals 18+ who are **not** residents of OFAC-sanctioned countries/regions.
- Teams of up to **five**. One Team Representative receives any prize and is responsible for sharing it.
- Employees/agents of Base and their household/immediate family are ineligible.
- "Projects that enable trading for US users are not eligible" (Quest Page FAQ). Winners undergo identity verification and tax obligations.
- Existing-token rule: teams that previously launched tokens are not eligible by default; they must ship a demonstrable stock-linked product or feature during the campaign. A relaunch does not reset the original launch date. New products (no token required) are in the "Build Something New" path.

## Tracks (Official Rules §3 + Quest Page)

The three official Tracks, judged separately:

1. **Meme and Community Economies** — "Build new ways to organize memes and communities around tokenized equities."
2. **Agentic Stock Finance** — "Build agents that research, earn or trade around tokenized stocks in novel ways." This is the parent track for idea **2.1**.
3. **Programmable Stock Markets** — "Create net-new stock market primitives, e.g., custom portfolios, indexes, structured products, financing tools, prediction markets, and market infrastructure."

Each Track Section (on the Quest Page) "describes the Track, gives any example ideas and 'Show us' guidance, and sets out the prizes." That accordion body did **not** render into the static HTML. The Track 2.1 idea and Show-us line used for this build come from the published brief quoted below, not from a second source.

### Track 2.1 — Agents that earn their stock treasury

- Idea (competition brief): an agent sells a service (research/API), gets paid in USDC via **x402**, and puts a **user-set share of its surplus** into tokenized stocks. Operating costs first. Loop: useful work → revenue → operating reserve → stock treasury.
- **Show us:** "a real payment funding a permitted stock purchase, with clear allocation rules and a reserve the agent can't invest."

## Judging (Official Rules §7)

- A panel chosen by the Sponsor scores eligible Submissions against **the criteria included on the Quest Page**, weighted equally unless the Quest Page sets different weights.
- Those criteria live in the Track Section and were **not in the static HTML**. Do not invent weights or criterion names.
- Judges' decisions are final. If a Track gets fewer than three eligible Submissions, Sponsor may award fewer prizes than posted; if it gets at least that many, every posted prize in that Track is awarded. Unawarded prizes are not moved across Tracks unless the Quest Page says otherwise.

## Launchpad / partner logos on the Quest Page

Partners displayed (logo carousel and/or track chips). This is a logo list, not a confirmation of a Partner Track prize or of testnet stock tokens:

- O1 Exchange
- Bankr
- BaseStonk
- Stonks Exchange
- Feel.cash
- Hydropump by Hydrex
- Base (track-chip on Agentic Stock Finance)

Agentic Stock Finance track chip shows **3 partners**: Base, Bankr, BaseStonk.

Partner Tracks (Official Rules §8) are posted on the Quest Page with the Partner's identity and prizes. Detailed Partner Track terms were in the same collapsed sections and were **not captured**.

No testnet stock-token addresses, no "supported stock tokens" list, and no Sepolia launchpad inventory appear on the Quest Page HTML that was fetched.

## Tokenized stocks on Base — mainnet only (as of this fetch)

`GET https://api.coinbase.com/v1/tokenized-stocks/chains` returned a **single** chain:

```json
{"chain_id":"8453","chain":"base",
 "policy_registry_address":"0x8453000000000000000000000000000000000002",
 "token_supply_manager_address":"0xD1Ca4dAcdf3231011D175351f1f02D15C7c5664C",
 "token_factory_address":"0x4bA3E29E254F25E94E61C4c9d67b37027331534D"}
```

No Base Sepolia (`84532`) entry. The Tokenized Stocks API is read-only reference data for Coinbase-issued tokens on Base mainnet. Presence in the API "does not imply trading availability or eligibility." Coinbase tokenized stocks are described as available only to persons in eligible jurisdictions outside the United States.

**Implication for a testnet entry:** there are no official Coinbase tokenized-stock contracts on Base Sepolia. This project uses **clearly labeled MOCK stock tokens and a MOCK AMM**, documented as such. They are not securities and give no rights in any public company.

## Networks, USDC, x402, faucets, bridge

- Base Mainnet: chain ID `8453`. **Out of scope — do not deploy or transact.**
- Base Sepolia: chain ID `84532`, RPC `https://sepolia.base.org`, explorer `https://sepolia.basescan.org`.
- Official Circle USDC on Base Sepolia (has contract code): `0x036CbD53842c5426634e7929541eC2318f3dCF7e`. The `…CF7c` address that appears in one Base x402 snippet has **no code** and is a documentation typo.
- x402 public facilitator is for testnets (Base docs). Client examples use network `eip155:84532` and the USDC address above. Scheme used in this build: `exact`.
- Official Base Sepolia ETH faucets (docs): Coinbase Developer Platform (up to 0.1 ETH / 24h, plus USDC/EURC/cbBTC; also CDP SDK), thirdweb, Alchemy (account), QuickNode, Chainstack (API key), ethfaucet.com. Test USDC: Circle faucet, select Base Sepolia.
- Official L1 Standard Bridge for Sepolia ETH → Base Sepolia ETH (from official contract list): `0xfd0Bf71F60660E2f608ed56e1659C450eB113120` on Ethereum Sepolia (`11155111`).

## Submission and legal constraints that affect the build

- Must be built on, or meaningfully integrate with, Base, and fit the Track (Rules §6).
- Must not misrepresent a relationship with or endorsement by Sponsor, any Partner, any issuer, or any public company. Must not claim voting or other rights in an underlying company that the asset does not provide.
- Must comply with securities and related laws. Track ideas are "for inspiration only" and are not a statement that a product is lawful (Rules §14).
- The Quest is not an offer to buy or sell any security.
- This entry is **testnet-only**, uses mock stock tokens, and is a competition prototype — not a production brokerage, not available to US users for trading, not investment advice.

## This entry's mapping to Track 2.1 "Show us"

| Show-us requirement | How this repo answers it |
| --- | --- |
| A real payment | x402 `exact` payment in USDC (EIP-3009 `receiveWithAuthorization`), locally on Anvil against MockUSDC, and on Base Sepolia against Circle USDC if the wallet can be funded |
| Funding a permitted stock purchase | Vault `allocate` swaps USDC through an allowlisted router to an allowlisted stock; anything else reverts |
| Clear allocation rules | On deposit/sync: fill operating-reserve target first; of the remainder, `allocationBps` becomes investable and the rest is retained cash the agent cannot invest |
| A reserve the agent can't invest | `allocate` and `payOperatingCost` both revert `ReserveBreach` if the USDC balance would fall below `operatingReserveTarget`. Only the human owner can withdraw reserve |
