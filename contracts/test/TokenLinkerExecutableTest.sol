// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import { IInterTokenExecutable } from '../interfaces/IInterTokenExecutable.sol';
import { IERC20 } from '../interfaces/IERC20.sol';

contract TokenLinkerExecutableTest is IInterTokenExecutable {
    string public val;

    function exectuteWithInterToken(
        address tokenAddress,
        string calldata,
        bytes calldata,
        uint256 amount,
        bytes calldata data
    ) external override {
        address to;
        (to, val) = abi.decode(data, (address, string));
        IERC20(tokenAddress).transfer(to, amount);
    }
}
