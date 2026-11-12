# Base Sepolia results (real transactions — not fabricated)

Recorded 2026-11-12 22:52:39 WIB. Wallet `0xA514D7E29abaEb5a4bc4932B0F488A4c20f69D22`. Explorer: [sepolia.basescan.org](https://sepolia.basescan.org).

## Funding

| Step | Detail | Link |
| --- | --- | --- |
| Official L1 Standard Bridge, 0.2 ETH, Ethereum Sepolia → Base Sepolia | Bridge `0xfd0Bf71F60660E2f608ed56e1659C450eB113120`. L1 block 12119817 at 2026-11-12 22:45:24 WIB. Status success. | [tx](https://sepolia.etherscan.io/tx/0x5929a37346f4e30aa7450dccec42599687a9b0fa9e4a103832addeb19c956a45) |
| L2 credit | 0.2 ETH arrived on Base Sepolia | [address](https://sepolia.basescan.org/address/0xA514D7E29abaEb5a4bc4932B0F488A4c20f69D22) |

Circle faucet (faucet.circle.com) is recaptcha-gated. CDP faucet requires a Coinbase Developer Portal login. No faucet API keys were present. So the vault uses **labeled MockUSDC** (EIP-3009) on Base Sepolia, not official Circle USDC (`0x036CbD53842c5426634e7929541eC2318f3dCF7e`). Official Coinbase tokenized stocks are mainnet-only; stock tokens are **MOCK**.

## Contracts

| Contract | Address | Create tx |
| --- | --- | --- |
| StockTreasuryVault | [`0xc6a9…238AE`](https://sepolia.basescan.org/address/0xc6a9c24316DF6305a2CA994C70e33E22eF1238AE) | [tx](https://sepolia.basescan.org/tx/0x33524318685f7548e9a2cd7eb37a12d3ce1152e26bbb3a815c04e88a2b5eabeb) |
| MockUSDC | [`0xa64f…80AA0`](https://sepolia.basescan.org/address/0xa64f084E7701d00058f6C39F59D5C8669b280AA0) | [tx](https://sepolia.basescan.org/tx/0xf2c6651bfe0d118662b3a37772f48ae4a993679bf2b4a88f00f26baf0e3d265e) |
| MockStockAMM | [`0x7845…FED0A`](https://sepolia.basescan.org/address/0x7845C91DccD74d8EF3d6A22Fa8C7809e9d8FED0A) | [tx](https://sepolia.basescan.org/tx/0x49f2932ce36519bcd6da5fb908670267bb255bf775a1c249173a078967421dfb) |
| MOCK-AAPL | [`0xA0BF…34aD47`](https://sepolia.basescan.org/address/0xA0BFD72a7259AE2B2eCcEDa0ae65f268b634aD47) | [tx](https://sepolia.basescan.org/tx/0x94a2c126cef95d22faea99cdaf0d96ee70b47774a68ed7197ab9d54134f3f91a) |
| MOCK-NVDA | [`0x5c1f…87Ac2`](https://sepolia.basescan.org/address/0x5c1f3d726AFe83e4e0dC31e82f16B5555c387Ac2) | [tx](https://sepolia.basescan.org/tx/0x4e22e71ba486eac8c914166a097f0fcbbdae74c67527a645d5b30091058cefbe) |
| setPolicy (70%, 50 USDC reserve, 40/80 caps) | | [tx](https://sepolia.basescan.org/tx/0x098ccaca8b05671868c18bd344ad4caef7c8eeb5df62b7bbba4f96f0d60d4f48) |

## Do X → see Y (live)

| What you do | What you see | Tx |
| --- | --- | --- |
| Buyer pays 150 USDC via x402 (EIP-3009 `transferWithAuthorization`) for a research brief | USDC lands in the vault | [tx](https://sepolia.basescan.org/tx/0x668fc1435496a3d1c5676f25a1e1f4a6d978d9e9205dea57aeab417c6eb64ec7) |
| Agent calls `syncRevenue` | Reserve 50, investable 70, retained 30 | [tx](https://sepolia.basescan.org/tx/0xac17b2dffa5bac27e4028de7d000642af04b480d97fb5bbd45971304f9f0727e) |
| Agent pays 10 USDC operating cost | Retained 20, reserve untouched | [tx](https://sepolia.basescan.org/tx/0x8ad63ce26e5699bed555222782fcc77d50ec06c72c8c495c17b76e0a697da927) |
| Agent allocates 40 USDC to MOCK-AAPL | 4 MOCK-AAPL in the vault; USDC 100 = 50 reserve + 30 investable + 20 retained | [tx](https://sepolia.basescan.org/tx/0x0a890f36482acfc01cbdd535ee40a6aa94c267d92ab5b6dd2a404cdfd299c2de) |
| Agent tries to spend the reserve (`payOperatingCost` of 50.000001 USDC) | **On-chain failure, status 0, `ReserveBreach`.** Vault USDC still 100. Block 57884315. | [tx](https://sepolia.basescan.org/tx/0x2cf00ca154dee4d76f565d134c0b857feaddc665fc7494df384331083da0b448) |
