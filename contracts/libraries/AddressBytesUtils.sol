// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

library AddressBytesUtils {

    function toAddress(bytes memory bytesAddress) internal pure returns (address addr) {
        assembly {
            addr := mload(add(bytesAddress, 20))
        } 
    }

   
}
