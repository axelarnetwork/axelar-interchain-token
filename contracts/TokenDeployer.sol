// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import { BurnableMintableCappedERC20 } from '@axelar-network/axelar-cgp-solidity/contracts/BurnableMintableCappedERC20.sol';

import { ITokenDeployer } from './interfaces/ITokenDeployer.sol';

contract TokenDeployer is ITokenDeployer {
    function deployToken(string calldata name, string calldata symbol, uint8 decimals, bytes32 salt) external override returns (address tokenAddress) {
        tokenAddress = address(new BurnableMintableCappedERC20{salt: salt}(name, symbol, decimals, 0));
        BurnableMintableCappedERC20(tokenAddress).transferOwnership(msg.sender);
    }
}