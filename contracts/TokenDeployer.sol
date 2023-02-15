// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import { BurnableMintableCappedERC20 } from '@axelar-network/axelar-cgp-solidity/contracts/BurnableMintableCappedERC20.sol';

import { ITokenDeployer } from './interfaces/ITokenDeployer.sol';

contract TokenDeployer is ITokenDeployer {
    function test() external view returns (address addr) {
        addr = address(this);
    }

    function deployToken(
        address owner,
        string calldata name,
        string calldata symbol,
        uint8 decimals,
        uint256 cap,
        bytes32 salt
    ) external returns (address tokenAddress) {
        tokenAddress = address(new BurnableMintableCappedERC20{ salt: salt }(name, symbol, decimals, cap));
        BurnableMintableCappedERC20(tokenAddress).transferOwnership(owner);
    }
}
