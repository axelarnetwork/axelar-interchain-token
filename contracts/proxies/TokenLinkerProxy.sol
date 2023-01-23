// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import { Proxy } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/upgradables/Proxy.sol';

contract TokenLinkerProxy is Proxy {
    // solhint-disable-next-line no-empty-blocks
    function contractId() internal pure override returns (bytes32) {
        return 0x6ec6af55bf1e5f27006bfa01248d73e8894ba06f23f8002b047607ff2b1944ba;
    }
}