// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script, console2} from "forge-std/Script.sol";
import {StockTreasuryVault} from "../src/StockTreasuryVault.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";

/// @notice Runs the judge-facing flow against an already-deployed local stack:
///         1. A payment (USDC transfer) lands in the vault.
///         2. Revenue is synced (reserve filled, surplus split).
///         3. The agent pays a small operating cost.
///         4. The agent allocates investable USDC to MOCK-AAPL.
///         5. The agent tries to spend the reserve and is rejected.
contract DemoFlow is Script {
    function run() external {
        uint256 pk = vm.envOr("LOCAL_PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));
        address deployer = vm.addr(pk);

        string memory raw = vm.readFile("deployments/local.json");
        address vaultAddr = vm.parseJsonAddress(raw, ".vault");
        address usdcAddr = vm.parseJsonAddress(raw, ".usdc");
        address aapl = vm.parseJsonAddress(raw, ".stocks[0].address");

        StockTreasuryVault vault = StockTreasuryVault(vaultAddr);
        MockUSDC usdc = MockUSDC(usdcAddr);

        vm.startBroadcast(pk);

        // 1-2. "x402 payment" equivalent: USDC arrives, then sync.
        usdc.transfer(vaultAddr, 150e6);
        vault.syncRevenue();
        console2.log("after payment + sync");
        console2.log("  balance   ", IERC20(usdcAddr).balanceOf(vaultAddr));
        console2.log("  investable", vault.investable());
        console2.log("  retained  ", vault.retained());

        // 3. Operating cost (10 USDC) from retained.
        vault.payOperatingCost(deployer, 10e6, bytes32("infra"));
        console2.log("after operating cost 10 USDC");
        console2.log("  balance   ", IERC20(usdcAddr).balanceOf(vaultAddr));
        console2.log("  investable", vault.investable());

        // 4. Permitted purchase: 40 USDC of MOCK-AAPL (4 shares at $10).
        uint256 out = vault.allocate(aapl, 40e6, 0);
        console2.log("allocated 40 USDC, stock out", out);
        console2.log("  MOCK-AAPL ", IERC20(aapl).balanceOf(vaultAddr));
        console2.log("  balance   ", IERC20(usdcAddr).balanceOf(vaultAddr));
        console2.log("  investable", vault.investable());

        vm.stopBroadcast();

        // 5. Reserve-breach attempt — simulated via a static call so the
        //    broadcasted demo stays clean, then also tried on-chain with a
        //    prank after broadcast. We record the revert selector.
        //    Remaining investable may still be > 0; to hit ReserveBreach we
        //    try payOperatingCost of (balance - reserve + 1).
        uint256 bal = IERC20(usdcAddr).balanceOf(vaultAddr);
        uint256 target = vault.operatingReserveTarget();
        uint256 drain = bal - target + 1;
        vm.prank(deployer);
        try vault.payOperatingCost(deployer, drain, bytes32("drain-reserve")) {
            console2.log("ERROR: reserve drain unexpectedly succeeded");
        } catch (bytes memory reason) {
            console2.log("reserve-breach rejected, revert bytes:", reason.length);
        }
    }
}
