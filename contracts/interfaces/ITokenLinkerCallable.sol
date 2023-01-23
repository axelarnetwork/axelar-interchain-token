// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

// General interface for upgradable contracts
interface ITokenLinkerCallable {
    function processToken(
        address tokenAddress,
        string calldata sourceChain,
        bytes calldata sourceAddress,
        uint256 amount,
        bytes calldata data
    ) external;
}
