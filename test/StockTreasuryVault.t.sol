// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console2} from "forge-std/Test.sol";
import {StockTreasuryVault} from "../src/StockTreasuryVault.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockStockToken} from "../src/mocks/MockStockToken.sol";
import {MockStockAMM} from "../src/mocks/MockStockAMM.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";

contract StockTreasuryVaultTest is Test {
    MockUSDC internal usdc;
    MockStockToken internal aapl;
    MockStockToken internal nvda;
    MockStockAMM internal amm;
    StockTreasuryVault internal vault;

    address internal owner = makeAddr("owner");
    address internal agent = makeAddr("agent");
    address internal buyer = makeAddr("buyer");
    address internal vendor = makeAddr("vendor");
    address internal stranger = makeAddr("stranger");

    uint16 internal constant ALLOC_BPS = 7000; // 70% of surplus is investable
    uint256 internal constant RESERVE = 50e6; // 50 USDC
    uint256 internal constant PER_TX = 40e6; // 40 USDC
    uint256 internal constant DAILY = 80e6; // 80 USDC
    uint256 internal constant AAPL_PRICE = 10e6; // 10 USDC per MOCK-AAPL
    uint256 internal constant NVDA_PRICE = 20e6;

    function setUp() public {
        vm.startPrank(owner);
        usdc = new MockUSDC();
        aapl = new MockStockToken("MOCK Apple Inc (TESTNET ONLY - NOT A SECURITY)", "MOCK-AAPL");
        nvda = new MockStockToken("MOCK NVIDIA Corp (TESTNET ONLY - NOT A SECURITY)", "MOCK-NVDA");
        amm = new MockStockAMM(address(usdc));
        amm.setPrice(address(aapl), AAPL_PRICE);
        amm.setPrice(address(nvda), NVDA_PRICE);
        aapl.mint(address(amm), 1_000_000e18);
        nvda.mint(address(amm), 1_000_000e18);

        vault = new StockTreasuryVault(address(usdc), owner, agent, address(amm));
        vault.setPolicy(ALLOC_BPS, RESERVE, PER_TX, DAILY);
        vault.setStockAllowed(address(aapl), true);
        vault.setStockAllowed(address(nvda), true);
        vault.setCostRecipient(vendor, true);
        usdc.mint(buyer, 1_000_000e6);
        usdc.mint(agent, 1_000e6);
        vm.stopPrank();
    }

    function _depositFrom(address from, uint256 amount) internal {
        vm.startPrank(from);
        usdc.approve(address(vault), amount);
        vault.deposit(amount);
        vm.stopPrank();
    }

    // ------------------------------------------------------------------
    // Allocation math
    // ------------------------------------------------------------------

    function test_depositFillsReserveFirstThenSplitsSurplus() public {
        // 50 reserve + 100 surplus → investable = 70, retained = 30
        _depositFrom(buyer, 150e6);
        StockTreasuryVault.Preview memory p = vault.preview();
        assertEq(p.usdcBalance, 150e6);
        assertEq(p.reservedEffective, 50e6);
        assertEq(p.investable, 70e6);
        assertEq(p.retained, 30e6);
        assertEq(vault.investable(), 70e6);
        assertEq(vault.retained(), 30e6);
    }

    function test_depositBelowReserveIsEntirelyReserved() public {
        _depositFrom(buyer, 40e6);
        StockTreasuryVault.Preview memory p = vault.preview();
        assertEq(p.reservedEffective, 40e6);
        assertEq(p.investable, 0);
        assertEq(p.retained, 0);
        assertEq(vault.maxAllocatable(), 0);
    }

    function test_secondDepositOnlySplitsNewSurplus() public {
        _depositFrom(buyer, 50e6); // fills reserve exactly
        _depositFrom(buyer, 100e6); // all surplus
        assertEq(vault.investable(), 70e6);
        assertEq(vault.retained(), 30e6);
        assertEq(usdc.balanceOf(address(vault)), 150e6);
    }

    function test_directTransferIsAccountedBySyncRevenue() public {
        // x402 facilitator transfers USDC straight to the vault
        vm.prank(buyer);
        usdc.transfer(address(vault), 150e6);
        // before sync, investable is still 0
        assertEq(vault.investable(), 0);
        vault.syncRevenue();
        assertEq(vault.investable(), 70e6);
        assertEq(vault.retained(), 30e6);
    }

    function test_allocateSuccessBuysAllowlistedStock() public {
        _depositFrom(buyer, 150e6);
        uint256 maxIn = 40e6; // per-tx cap
        uint256 expectedOut = (maxIn * 1e18) / AAPL_PRICE; // 4 whole MOCK-AAPL

        vm.prank(agent);
        uint256 out = vault.allocate(address(aapl), maxIn, expectedOut);

        assertEq(out, expectedOut);
        assertEq(aapl.balanceOf(address(vault)), expectedOut);
        assertEq(usdc.balanceOf(address(vault)), 110e6); // 150 - 40
        assertEq(vault.investable(), 30e6); // 70 - 40
        assertEq(vault.retained(), 30e6); // unchanged
        assertEq(vault.preview().reservedEffective, 50e6);
    }

    function test_allocateEmitsAllocated() public {
        _depositFrom(buyer, 150e6);
        vm.expectEmit(true, true, false, true);
        emit StockTreasuryVault.Allocated(agent, address(aapl), 40e6, 4e18, 30e6);
        vm.prank(agent);
        vault.allocate(address(aapl), 40e6, 0);
    }

    // ------------------------------------------------------------------
    // Reserve breach - the headline Show-us rejection
    // ------------------------------------------------------------------

    function test_allocateRevertsReserveBreach() public {
        // Fill reserve only. investable = 0, but we also force a situation
        // where investable has been credited and a later target rise (or a
        // crafted amount) would dip into the reserve.
        _depositFrom(buyer, 50e6);
        assertEq(vault.investable(), 0);

        vm.prank(agent);
        vm.expectRevert(
            abi.encodeWithSelector(StockTreasuryVault.ExceedsInvestable.selector, 1e6, uint256(0))
        );
        vault.allocate(address(aapl), 1e6, 0);
    }

    function test_reserveBreachWhenInvestableWouldCrossFloor() public {
        // 50 reserve + 70 investable + 30 retained. Raise the reserve target
        // so that spending current investable would breach the new floor.
        _depositFrom(buyer, 150e6);
        vm.prank(owner);
        vault.setPolicy(ALLOC_BPS, 130e6, PER_TX, DAILY); // new floor 130
        // clamp: balance 150, reserved 130, investable shrinks to 20
        assertEq(vault.investable(), 20e6);

        // Trying to spend 21 (even if we could) would breach. 20 is the clamped max.
        // Spend 20 - remaining 130, exactly the floor, OK.
        vm.prank(agent);
        vault.allocate(address(aapl), 20e6, 0);
        assertEq(usdc.balanceOf(address(vault)), 130e6);

        // Any further allocate, even 1 unit, is a reserve breach (investable is 0
        // after clamp, so we get ExceedsInvestable). To hit ReserveBreach itself
        // we temporarily credit investable via a direct storage poke is not
        // available; instead payOperatingCost with a would-be dip is tested below.
        vm.prank(agent);
        vm.expectRevert(
            abi.encodeWithSelector(StockTreasuryVault.ExceedsInvestable.selector, 1, uint256(0))
        );
        vault.allocate(address(aapl), 1, 0);
    }

    function test_payOperatingCostRevertsReserveBreach() public {
        _depositFrom(buyer, 50e6); // only reserve
        vm.prank(agent);
        vm.expectRevert(
            abi.encodeWithSelector(StockTreasuryVault.ReserveBreach.selector, uint256(50e6), uint256(1e6), RESERVE)
        );
        vault.payOperatingCost(vendor, 1e6, bytes32("gas"));
    }

    function test_payOperatingCostSucceedsFromRetainedThenInvestable() public {
        _depositFrom(buyer, 150e6); // reserved 50, inv 70, ret 30
        vm.prank(agent);
        vault.payOperatingCost(vendor, 40e6, bytes32("inference"));
        // 30 from retained, 10 from investable
        assertEq(usdc.balanceOf(vendor), 40e6);
        assertEq(usdc.balanceOf(address(vault)), 110e6);
        assertEq(vault.investable(), 60e6);
        assertEq(vault.retained(), 0); // 110 - 50 - 60
        assertEq(vault.preview().reservedEffective, 50e6);
    }

    // ------------------------------------------------------------------
    // Caps, allowlist, pause, roles
    // ------------------------------------------------------------------

    function test_allocateRevertsPerTxCap() public {
        _depositFrom(buyer, 200e6); // surplus 150, inv 105
        vm.prank(agent);
        vm.expectRevert(
            abi.encodeWithSelector(StockTreasuryVault.PerTxCapExceeded.selector, uint256(41e6), PER_TX)
        );
        vault.allocate(address(aapl), 41e6, 0);
    }

    function test_allocateRevertsDailyCapAndResetsNextDay() public {
        _depositFrom(buyer, 500e6); // plenty of investable (0.7 * 450 = 315)
        vm.startPrank(agent);
        vault.allocate(address(aapl), 40e6, 0);
        vault.allocate(address(aapl), 40e6, 0); // daily used = 80, at cap
        vm.expectRevert(
            abi.encodeWithSelector(StockTreasuryVault.DailyCapExceeded.selector, uint256(1e6), uint256(80e6), DAILY)
        );
        vault.allocate(address(aapl), 1e6, 0);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);
        vm.prank(agent);
        vault.allocate(address(aapl), 40e6, 0); // new day, OK
        assertEq(vault.dailyUsed(), 40e6);
    }

    function test_allocateRevertsStockNotAllowed() public {
        _depositFrom(buyer, 150e6);
        MockStockToken eviltok = new MockStockToken("MOCK Evil", "MOCK-EVIL");
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(StockTreasuryVault.StockNotAllowed.selector, address(eviltok)));
        vault.allocate(address(eviltok), 10e6, 0);
    }

    function test_allocateRevertsWhenStockDisallowedLater() public {
        _depositFrom(buyer, 150e6);
        vm.prank(owner);
        vault.setStockAllowed(address(aapl), false);
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(StockTreasuryVault.StockNotAllowed.selector, address(aapl)));
        vault.allocate(address(aapl), 10e6, 0);
    }

    function test_allocateRevertsWhenPaused() public {
        _depositFrom(buyer, 150e6);
        vm.prank(owner);
        vault.pause();
        vm.prank(agent);
        vm.expectRevert(StockTreasuryVault.Paused.selector);
        vault.allocate(address(aapl), 10e6, 0);
        // unpause restores
        vm.prank(owner);
        vault.unpause();
        vm.prank(agent);
        vault.allocate(address(aapl), 10e6, 0);
    }

    function test_strangerCannotAllocate() public {
        _depositFrom(buyer, 150e6);
        vm.prank(stranger);
        vm.expectRevert(StockTreasuryVault.NotAgent.selector);
        vault.allocate(address(aapl), 10e6, 0);
    }

    function test_agentCannotSetPolicyOrWithdraw() public {
        _depositFrom(buyer, 150e6);
        vm.startPrank(agent);
        vm.expectRevert(StockTreasuryVault.NotOwner.selector);
        vault.setPolicy(10000, 0, 1, 1);
        vm.expectRevert(StockTreasuryVault.NotOwner.selector);
        vault.pause();
        vm.expectRevert(StockTreasuryVault.NotOwner.selector);
        vault.setStockAllowed(address(aapl), false);
        vm.expectRevert(StockTreasuryVault.NotOwner.selector);
        vault.ownerWithdraw(address(usdc), agent, 50e6);
        vm.stopPrank();
        // reserve still intact
        assertEq(usdc.balanceOf(address(vault)), 150e6);
    }

    function test_ownerCanWithdrawReserve() public {
        _depositFrom(buyer, 150e6);
        vm.prank(owner);
        vault.ownerWithdraw(address(usdc), owner, 50e6);
        assertEq(usdc.balanceOf(owner), 50e6);
        assertEq(usdc.balanceOf(address(vault)), 100e6);
        // investable clamped to 100 - 50 (new effective reserve still 50) = 50? 
        // lastAccounted = 100, investable was 70, 70+50=120 > 100, clamp to 50
        assertEq(vault.investable(), 50e6);
        assertEq(vault.preview().reservedEffective, 50e6);
    }

    function test_ownerWithdrawStocks() public {
        _depositFrom(buyer, 150e6);
        vm.prank(agent);
        vault.allocate(address(aapl), 40e6, 0);
        uint256 held = aapl.balanceOf(address(vault));
        vm.prank(owner);
        vault.ownerWithdraw(address(aapl), owner, held);
        assertEq(aapl.balanceOf(owner), held);
        assertEq(aapl.balanceOf(address(vault)), 0);
    }

    function test_payOperatingCostRevertsUnallowlistedRecipient() public {
        _depositFrom(buyer, 150e6);
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(StockTreasuryVault.CostRecipientNotAllowed.selector, stranger));
        vault.payOperatingCost(stranger, 1e6, bytes32("x"));
    }

    function test_depositRevertsWhenPolicyNotSet() public {
        vm.prank(owner);
        StockTreasuryVault bare = new StockTreasuryVault(address(usdc), owner, agent, address(amm));
        vm.startPrank(buyer);
        usdc.approve(address(bare), 10e6);
        vm.expectRevert(StockTreasuryVault.PolicyNotSet.selector);
        bare.deposit(10e6);
        vm.stopPrank();
    }

    function test_setPolicyRejectsInvalidBpsAndZeroCaps() public {
        vm.startPrank(owner);
        vm.expectRevert(StockTreasuryVault.InvalidBps.selector);
        vault.setPolicy(10001, RESERVE, PER_TX, DAILY);
        vm.expectRevert(StockTreasuryVault.InvalidCap.selector);
        vault.setPolicy(ALLOC_BPS, RESERVE, 0, DAILY);
        vm.expectRevert(StockTreasuryVault.InvalidCap.selector);
        vault.setPolicy(ALLOC_BPS, RESERVE, PER_TX, 0);
        vm.stopPrank();
    }

    function test_killSwitchCannotBeToggledByAgent() public {
        vm.prank(agent);
        vm.expectRevert(StockTreasuryVault.NotOwner.selector);
        vault.pause();
    }

    function test_allocationBpsZeroMeansNothingInvestable() public {
        vm.prank(owner);
        vault.setPolicy(0, RESERVE, PER_TX, DAILY);
        _depositFrom(buyer, 150e6);
        assertEq(vault.investable(), 0);
        assertEq(vault.retained(), 100e6);
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(StockTreasuryVault.ExceedsInvestable.selector, 1e6, uint256(0)));
        vault.allocate(address(aapl), 1e6, 0);
    }

    function test_allocationBpsFullSurplusIsInvestableButReserveStands() public {
        vm.prank(owner);
        vault.setPolicy(10_000, RESERVE, 100e6, 200e6);
        _depositFrom(buyer, 150e6);
        assertEq(vault.investable(), 100e6);
        assertEq(vault.retained(), 0);
        vm.prank(agent);
        vault.allocate(address(aapl), 100e6, 0);
        assertEq(usdc.balanceOf(address(vault)), 50e6);
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(StockTreasuryVault.ExceedsInvestable.selector, 1, uint256(0)));
        vault.allocate(address(aapl), 1, 0);
    }

    function test_holdingsAndMaxAllocatable() public {
        _depositFrom(buyer, 150e6);
        assertEq(vault.maxAllocatable(), 40e6); // per-tx
        vm.prank(agent);
        vault.allocate(address(aapl), 40e6, 0);
        (address[] memory toks, uint256[] memory bals) = vault.holdings();
        assertEq(toks.length, 2);
        assertEq(toks[0], address(aapl));
        assertEq(bals[0], 4e18);
        assertEq(bals[1], 0);
        assertEq(vault.maxAllocatable(), 30e6); // remaining investable, under per-tx
    }

    function test_zeroAmountReverts() public {
        _depositFrom(buyer, 150e6);
        vm.prank(agent);
        vm.expectRevert(StockTreasuryVault.ZeroAmount.selector);
        vault.allocate(address(aapl), 0, 0);
    }

    function test_depositRevertsWhenPaused() public {
        vm.prank(owner);
        vault.pause();
        vm.startPrank(buyer);
        usdc.approve(address(vault), 10e6);
        vm.expectRevert(StockTreasuryVault.Paused.selector);
        vault.deposit(10e6);
        vm.stopPrank();
    }

    function test_twoStocksCanBeBought() public {
        _depositFrom(buyer, 200e6); // surplus 150, inv 105
        vm.startPrank(agent);
        vault.allocate(address(aapl), 10e6, 0); // 1 MOCK-AAPL
        vault.allocate(address(nvda), 20e6, 0); // 1 MOCK-NVDA
        vm.stopPrank();
        assertEq(aapl.balanceOf(address(vault)), 1e18);
        assertEq(nvda.balanceOf(address(vault)), 1e18);
    }

    function test_transferOwnership() public {
        address newOwner = makeAddr("newOwner");
        vm.prank(owner);
        vault.transferOwnership(newOwner);
        vm.prank(owner);
        vm.expectRevert(StockTreasuryVault.NotOwner.selector);
        vault.pause();
        vm.prank(newOwner);
        vault.pause();
        assertTrue(vault.paused());
    }

    // ------------------------------------------------------------------
    // EIP-3009 payment funds a permitted purchase (local "real payment")
    // ------------------------------------------------------------------

    function test_eip3009PaymentFundsAllocate() public {
        uint256 payerKey = 0xA11CE;
        address payer = vm.addr(payerKey);
        vm.prank(owner);
        usdc.mint(payer, 150e6);

        uint256 amount = 150e6;
        uint256 validAfter = 0;
        uint256 validBefore = block.timestamp + 1 hours;
        bytes32 nonce = keccak256("payment-1");

        bytes32 structHash = keccak256(
            abi.encode(
                usdc.TRANSFER_WITH_AUTHORIZATION_TYPEHASH(),
                payer,
                address(vault),
                amount,
                validAfter,
                validBefore,
                nonce
            )
        );
        bytes32 digest = keccak256(abi.encodePacked(hex"1901", usdc.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(payerKey, digest);

        usdc.transferWithAuthorization(payer, address(vault), amount, validAfter, validBefore, nonce, v, r, s);
        assertEq(usdc.balanceOf(address(vault)), 150e6);

        vault.syncRevenue();
        assertEq(vault.investable(), 70e6);

        vm.prank(agent);
        vault.allocate(address(aapl), 40e6, 4e18);
        assertEq(aapl.balanceOf(address(vault)), 4e18);
        assertEq(usdc.balanceOf(address(vault)), 110e6);
    }

    function test_eip3009RejectsReplay() public {
        uint256 payerKey = 0xB0B;
        address payer = vm.addr(payerKey);
        vm.prank(owner);
        usdc.mint(payer, 150e6);
        uint256 amount = 150e6;
        bytes32 nonce = keccak256("once");
        bytes32 structHash = keccak256(
            abi.encode(
                usdc.TRANSFER_WITH_AUTHORIZATION_TYPEHASH(),
                payer,
                address(vault),
                amount,
                uint256(0),
                block.timestamp + 1 hours,
                nonce
            )
        );
        bytes32 digest = keccak256(abi.encodePacked(hex"1901", usdc.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(payerKey, digest);
        usdc.transferWithAuthorization(payer, address(vault), amount, 0, block.timestamp + 1 hours, nonce, v, r, s);
        vm.expectRevert(MockUSDC.AuthorizationAlreadyUsed.selector);
        usdc.transferWithAuthorization(payer, address(vault), amount, 0, block.timestamp + 1 hours, nonce, v, r, s);
    }
}
