// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

interface ITokenDeployer {
    function test() external returns (address addr);

    function deployToken(
        address owner,
        string calldata name,
        string calldata symbol,
        uint8 decimals,
        uint256 cap,
        bytes32 salt
    ) external payable returns (address tokenAddress);
}
