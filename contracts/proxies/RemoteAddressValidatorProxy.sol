// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import { Proxy } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/upgradables/Proxy.sol';

contract RemoteAddressValidatorProxy is Proxy {
    // solhint-disable-next-line no-empty-blocks
    function contractId() internal pure override returns (bytes32) {
        return 0x5d9f4d5e6bb737c289f92f2a319c66ba484357595194acb7c2122e48550eda7c;
    }
}