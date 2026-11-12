// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "../interfaces/IERC20.sol";

library SafeERC20 {
    error SafeERC20Failed();

    function safeTransfer(IERC20 token, address to, uint256 amount) internal {
        _call(token, abi.encodeWithSelector(token.transfer.selector, to, amount));
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 amount) internal {
        _call(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, amount));
    }

    /// @dev Resets to zero first so USDC-style tokens that reject non-zero→non-zero allowance changes work.
    function forceApprove(IERC20 token, address spender, uint256 amount) internal {
        _call(token, abi.encodeWithSelector(token.approve.selector, spender, 0));
        if (amount != 0) {
            _call(token, abi.encodeWithSelector(token.approve.selector, spender, amount));
        }
    }

    function _call(IERC20 token, bytes memory data) private {
        (bool ok, bytes memory ret) = address(token).call(data);
        if (!ok) revert SafeERC20Failed();
        if (ret.length > 0 && !abi.decode(ret, (bool))) revert SafeERC20Failed();
    }
}
