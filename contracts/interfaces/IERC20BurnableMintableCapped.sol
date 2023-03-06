// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import { IERC20 } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IERC20.sol';

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20BurnableMintableCapped is IERC20 {
    error CapExceeded();

    function cap() external view returns (uint256);

    function mint(address to, uint256 amount) external;

    function burnFrom(address from, uint256 amount) external;
}
