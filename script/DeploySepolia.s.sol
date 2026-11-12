// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script, console2} from "forge-std/Script.sol";
import {StockTreasuryVault} from "../src/StockTreasuryVault.sol";
import {MockStockToken} from "../src/mocks/MockStockToken.sol";
import {MockStockAMM} from "../src/mocks/MockStockAMM.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";

/// @notice Base Sepolia (84532) ONLY. Refuses to broadcast on any other chain.
///         Uses official Circle USDC if USE_CIRCLE_USDC=true (and the deployer
///         already holds some), otherwise deploys MockUSDC labeled as such.
///         Always deploys MOCK stock tokens — there are no official Coinbase
///         tokenized stocks on Base Sepolia (API chains list is mainnet-only).
///
/// The private key is read from QDAY_PRIVATE_KEY via vm.envUint and is never logged.
contract DeploySepolia is Script {
    uint256 internal constant BASE_SEPOLIA = 84532;
    address internal constant CIRCLE_USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;

    function run() external {
        if (block.chainid != BASE_SEPOLIA) {
            revert(string.concat("Refusing to deploy: chainid ", vm.toString(block.chainid), " is not Base Sepolia 84532"));
        }
        uint256 pk = vm.envUint("QDAY_PRIVATE_KEY");
        address deployer = vm.addr(pk);
        address agent = vm.envOr("AGENT_ADDRESS", deployer);
        bool useCircle = vm.envOr("USE_CIRCLE_USDC", false);

        vm.startBroadcast(pk);

        address usdcAddr;
        if (useCircle) {
            usdcAddr = CIRCLE_USDC;
        } else {
            MockUSDC mock = new MockUSDC();
            mock.mint(deployer, 1_000_000e6);
            usdcAddr = address(mock);
        }

        MockStockToken aapl = new MockStockToken("MOCK Apple Inc (TESTNET ONLY - NOT A SECURITY)", "MOCK-AAPL");
        MockStockToken nvda = new MockStockToken("MOCK NVIDIA Corp (TESTNET ONLY - NOT A SECURITY)", "MOCK-NVDA");
        MockStockAMM amm = new MockStockAMM(usdcAddr);
        amm.setPrice(address(aapl), 10e6);
        amm.setPrice(address(nvda), 20e6);
        aapl.mint(address(amm), 1_000_000e18);
        nvda.mint(address(amm), 1_000_000e18);

        StockTreasuryVault vault = new StockTreasuryVault(usdcAddr, deployer, agent, address(amm));
        vault.setPolicy(7000, 50e6, 40e6, 80e6);
        vault.setStockAllowed(address(aapl), true);
        vault.setStockAllowed(address(nvda), true);
        vault.setCostRecipient(deployer, true);

        vm.stopBroadcast();

        string memory json = string.concat(
            "{\n",
            '  "network": "base-sepolia",\n',
            '  "chainId": 84532,\n',
            '  "explorer": "https://sepolia.basescan.org",\n',
            '  "usdc": "', vm.toString(usdcAddr), '",\n',
            '  "usdcKind": "', useCircle ? "circle-official" : "mock", '",\n',
            '  "vault": "', vm.toString(address(vault)), '",\n',
            '  "router": "', vm.toString(address(amm)), '",\n',
            '  "agent": "', vm.toString(agent), '",\n',
            '  "owner": "', vm.toString(deployer), '",\n',
            '  "stocks": [\n',
            '    {"symbol": "MOCK-AAPL", "name": "MOCK Apple Inc (TESTNET ONLY - NOT A SECURITY)", "address": "',
            vm.toString(address(aapl)), '", "priceUsdc": 10.0, "disclaimer": "MOCK / TESTNET ONLY. Not a security."},\n',
            '    {"symbol": "MOCK-NVDA", "name": "MOCK NVIDIA Corp (TESTNET ONLY - NOT A SECURITY)", "address": "',
            vm.toString(address(nvda)), '", "priceUsdc": 20.0, "disclaimer": "MOCK / TESTNET ONLY. Not a security."}\n',
            "  ],\n",
            '  "policy": {"allocationBps": 7000, "operatingReserveTarget": "50000000", "perTxCap": "40000000", "dailyCap": "80000000"},\n',
            '  "mockStocks": true,\n',
            '  "notes": "Mock stock tokens. Official Coinbase tokenized stocks are Base mainnet only (chain 8453). This deploy is Base Sepolia only."\n',
            "}\n"
        );
        vm.writeFile("deployments/base-sepolia.json", json);
        console2.log("chain", block.chainid);
        console2.log("deployer", deployer);
        console2.log("USDC", usdcAddr);
        console2.log("VAULT", address(vault));
        console2.log("AAPL", address(aapl));
        console2.log("NVDA", address(nvda));
        console2.log("AMM", address(amm));
    }
}
