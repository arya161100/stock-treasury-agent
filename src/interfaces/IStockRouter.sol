// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @notice Allowlisted swap adapter used by the vault to buy stock tokens with USDC.
/// @dev On Base Sepolia this is a MOCK AMM. It is not a production DEX and not a securities venue.
interface IStockRouter {
    function swapExactUSDCForStock(address stock, uint256 usdcIn, uint256 minOut, address to)
        external
        returns (uint256 stockOut);
}
