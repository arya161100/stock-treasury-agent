// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {MockERC20} from "./MockERC20.sol";

/// @title MockStockToken
/// @notice CLEARLY LABELED MOCK. This is NOT a tokenized security, is NOT
///         issued by Coinbase or any public company, and confers NO rights
///         (economic, voting, or otherwise) in any underlying equity.
///         It exists only so a Base Sepolia / local demo can show a permitted
///         "stock" purchase. Official Coinbase tokenized stocks are mainnet-only
///         (chain 8453) as of the date of this repo.
contract MockStockToken is MockERC20 {
    address public owner;
    string public constant DISCLAIMER =
        "MOCK / TESTNET ONLY. Not a security. Not affiliated with the named company.";

    error NotOwner();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(string memory name_, string memory symbol_) MockERC20(name_, symbol_, 18) {
        owner = msg.sender;
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "TO");
        owner = newOwner;
    }
}
