// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "../interfaces/IERC20.sol";
import {IStockRouter} from "../interfaces/IStockRouter.sol";
import {SafeERC20} from "../lib/SafeERC20.sol";

/// @title MockStockAMM
/// @notice A fixed-price swapper used ONLY on testnet / Anvil. It is not a
///         Uniswap pool, not a securities exchange, and not a real market.
///         Price is `usdcUnits` (6 decimals) per 1 whole stock token (1e18).
///         Example: price = 10_000_000 means 10 USDC buys 1 MOCK-AAPL.
contract MockStockAMM is IStockRouter {
    using SafeERC20 for IERC20;

    error NotOwner();
    error ZeroAddress();
    error ZeroAmount();
    error UnknownStock(address stock);
    error Slippage(uint256 out, uint256 minOut);
    error InsufficientInventory(uint256 need, uint256 have);

    event PriceSet(address indexed stock, uint256 usdcPerWhole);
    event Swapped(address indexed buyer, address indexed stock, uint256 usdcIn, uint256 stockOut);

    IERC20 public immutable usdc;
    address public owner;
    mapping(address => uint256) public usdcPerWhole; // 6-dec USDC per 1e18 stock

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address usdc_) {
        if (usdc_ == address(0)) revert ZeroAddress();
        usdc = IERC20(usdc_);
        owner = msg.sender;
    }

    function setPrice(address stock, uint256 usdcPerWhole_) external onlyOwner {
        if (stock == address(0)) revert ZeroAddress();
        if (usdcPerWhole_ == 0) revert ZeroAmount();
        usdcPerWhole[stock] = usdcPerWhole_;
        emit PriceSet(stock, usdcPerWhole_);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        owner = newOwner;
    }

    /// @inheritdoc IStockRouter
    function swapExactUSDCForStock(address stock, uint256 usdcIn, uint256 minOut, address to)
        external
        override
        returns (uint256 stockOut)
    {
        if (usdcIn == 0) revert ZeroAmount();
        if (to == address(0)) revert ZeroAddress();
        uint256 price = usdcPerWhole[stock];
        if (price == 0) revert UnknownStock(stock);

        // stockOut = usdcIn * 1e18 / price
        stockOut = (usdcIn * 1e18) / price;
        if (stockOut < minOut) revert Slippage(stockOut, minOut);

        uint256 inv = IERC20(stock).balanceOf(address(this));
        if (inv < stockOut) revert InsufficientInventory(stockOut, inv);

        usdc.safeTransferFrom(msg.sender, address(this), usdcIn);
        IERC20(stock).transfer(to, stockOut);
        emit Swapped(msg.sender, stock, usdcIn, stockOut);
    }

    /// @notice Quoted stock-token amount (18 decimals) for a USDC input (6 decimals).
    function quote(address stock, uint256 usdcIn) external view returns (uint256) {
        uint256 price = usdcPerWhole[stock];
        if (price == 0 || usdcIn == 0) return 0;
        return (usdcIn * 1e18) / price;
    }
}
