// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {StockTreasuryVault} from "../src/StockTreasuryVault.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockStockToken} from "../src/mocks/MockStockToken.sol";
import {MockStockAMM} from "../src/mocks/MockStockAMM.sol";

/// @notice Handler that only exposes agent-level actions. The invariant is:
///         after any sequence of agent calls, vault USDC >= operatingReserveTarget
///         whenever the vault has ever been funded to at least the target.
contract AgentHandler is Test {
    StockTreasuryVault public vault;
    MockUSDC public usdc;
    MockStockToken public aapl;
    address public agent;
    address public vendor;
    address public buyer;

    constructor(
        StockTreasuryVault vault_,
        MockUSDC usdc_,
        MockStockToken aapl_,
        address agent_,
        address vendor_,
        address buyer_
    ) {
        vault = vault_;
        usdc = usdc_;
        aapl = aapl_;
        agent = agent_;
        vendor = vendor_;
        buyer = buyer_;
    }

    function deposit(uint256 amount) external {
        amount = bound(amount, 1e6, 200e6);
        vm.prank(buyer);
        usdc.approve(address(vault), amount);
        vm.prank(buyer);
        vault.deposit(amount);
    }

    function allocate(uint256 amount) external {
        uint256 maxA = vault.maxAllocatable();
        if (maxA == 0) return;
        amount = bound(amount, 1, maxA);
        vm.prank(agent);
        vault.allocate(address(aapl), amount, 0);
    }

    function tryOverAllocate(uint256 extra) external {
        // Deliberately attempt a reserve-breaching or over-investable amount.
        // Must revert; the handler swallows the revert so the invariant can be checked.
        extra = bound(extra, 1, 500e6);
        uint256 amt = vault.investable() + extra;
        vm.prank(agent);
        try vault.allocate(address(aapl), amt, 0) {} catch {}
    }

    function payCost(uint256 amount) external {
        uint256 bal = usdc.balanceOf(address(vault));
        uint256 target = vault.operatingReserveTarget();
        if (bal <= target) return;
        uint256 room = bal - target;
        amount = bound(amount, 1, room);
        vm.prank(agent);
        try vault.payOperatingCost(vendor, amount, bytes32("cost")) {} catch {}
    }

    function tryPayFromReserve(uint256 extra) external {
        uint256 bal = usdc.balanceOf(address(vault));
        uint256 target = vault.operatingReserveTarget();
        uint256 amt = (bal > target ? bal - target : 0) + bound(extra, 1, 100e6);
        if (amt == 0) amt = 1;
        vm.prank(agent);
        try vault.payOperatingCost(vendor, amt, bytes32("drain")) {} catch {}
    }
}

contract InvariantsTest is Test {
    MockUSDC internal usdc;
    MockStockToken internal aapl;
    MockStockAMM internal amm;
    StockTreasuryVault internal vault;
    AgentHandler internal handler;

    address internal owner = makeAddr("owner");
    address internal agent = makeAddr("agent");
    address internal buyer = makeAddr("buyer");
    address internal vendor = makeAddr("vendor");

    function setUp() public {
        vm.startPrank(owner);
        usdc = new MockUSDC();
        aapl = new MockStockToken("MOCK Apple Inc (TESTNET ONLY - NOT A SECURITY)", "MOCK-AAPL");
        amm = new MockStockAMM(address(usdc));
        amm.setPrice(address(aapl), 10e6);
        aapl.mint(address(amm), 10_000_000e18);
        vault = new StockTreasuryVault(address(usdc), owner, agent, address(amm));
        vault.setPolicy(7000, 50e6, 40e6, 500e6);
        vault.setStockAllowed(address(aapl), true);
        vault.setCostRecipient(vendor, true);
        usdc.mint(buyer, 10_000_000e6);
        vm.stopPrank();

        handler = new AgentHandler(vault, usdc, aapl, agent, vendor, buyer);
        // The buyer needs to have approved the handler? Handler pranks buyer.
        targetContract(address(handler));
    }

    /// @dev The agent can never push vault USDC below the reserve once the vault
    ///      has been filled to the target. If the vault is still being filled,
    ///      the balance is just whatever has been deposited (also >= 0, trivially).
    function invariant_agentCannotBreachReserve() public view {
        uint256 bal = usdc.balanceOf(address(vault));
        uint256 target = vault.operatingReserveTarget();
        if (vault.lastAccounted() >= target) {
            assertGe(bal, target, "ReserveBreach: agent left the vault below its floor");
        }
    }

    function invariant_investableDoesNotExceedHeadroom() public view {
        uint256 bal = usdc.balanceOf(address(vault));
        uint256 reserved = bal < vault.operatingReserveTarget() ? bal : vault.operatingReserveTarget();
        assertLe(vault.preview().investable + reserved, bal);
    }

    function invariant_previewSplitsSumToBalance() public view {
        StockTreasuryVault.Preview memory p = vault.preview();
        assertEq(p.reservedEffective + p.investable + p.retained, p.usdcBalance);
    }
}
