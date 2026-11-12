// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script, console2} from "forge-std/Script.sol";
import {StockTreasuryVault} from "../src/StockTreasuryVault.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockStockToken} from "../src/mocks/MockStockToken.sol";
import {MockStockAMM} from "../src/mocks/MockStockAMM.sol";

/// @notice Deploys the full local stack (MockUSDC, mock stocks, mock AMM, vault)
///         and writes deployments/local.json for the dashboard and agent.
contract DeployLocal is Script {
    function run() external {
        uint256 pk = vm.envOr("LOCAL_PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));
        address deployer = vm.addr(pk);
        address agent = vm.envOr("AGENT_ADDRESS", deployer);

        vm.startBroadcast(pk);

        MockUSDC usdc = new MockUSDC();
        MockStockToken aapl = new MockStockToken("MOCK Apple Inc (TESTNET ONLY - NOT A SECURITY)", "MOCK-AAPL");
        MockStockToken nvda = new MockStockToken("MOCK NVIDIA Corp (TESTNET ONLY - NOT A SECURITY)", "MOCK-NVDA");
        MockStockAMM amm = new MockStockAMM(address(usdc));
        amm.setPrice(address(aapl), 10e6);
        amm.setPrice(address(nvda), 20e6);
        aapl.mint(address(amm), 1_000_000e18);
        nvda.mint(address(amm), 1_000_000e18);

        StockTreasuryVault vault = new StockTreasuryVault(address(usdc), deployer, agent, address(amm));
        vault.setPolicy(7000, 50e6, 40e6, 80e6);
        vault.setStockAllowed(address(aapl), true);
        vault.setStockAllowed(address(nvda), true);
        vault.setCostRecipient(deployer, true);

        // Fund a demo buyer with MockUSDC so the x402 service can be paid.
        usdc.mint(deployer, 1_000_000e6);

        vm.stopBroadcast();

        string memory json = string.concat(
            "{\n",
            '  "network": "anvil",\n',
            '  "chainId": ', vm.toString(block.chainid), ',\n',
            '  "usdc": "', vm.toString(address(usdc)), '",\n',
            '  "usdcName": "USD Coin (Mock, testnet only)",\n',
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
            '  "mock": true,\n',
            '  "notes": "Mock stock tokens. Official Coinbase tokenized stocks are Base mainnet only (chain 8453)."\n',
            "}\n"
        );
        vm.writeFile("deployments/local.json", json);
        console2.log("USDC  ", address(usdc));
        console2.log("VAULT ", address(vault));
        console2.log("AAPL  ", address(aapl));
        console2.log("NVDA  ", address(nvda));
        console2.log("AMM   ", address(amm));
        console2.log("wrote deployments/local.json");
    }
}
