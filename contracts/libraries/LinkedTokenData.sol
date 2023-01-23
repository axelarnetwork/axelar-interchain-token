// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

library LinkedTokenData {
    bytes32 public constant IS_NATIVE_MASK = bytes32(uint256(0x80 << 248));
    bytes32 public constant IS_GATEWAY_MASK = bytes32(uint256(0x40 << 248));
    bytes32 public constant LENGTH_MASK = bytes32(uint256(0x0f << 248));

    function getAddress(bytes32 tokenData) internal pure returns (address) {
        return address(uint160(uint256((tokenData))));
    }

    function isNative(bytes32 tokenData) internal pure returns (bool) {
        return tokenData & IS_NATIVE_MASK == IS_NATIVE_MASK;
    }
    function isGateway(bytes32 tokenData) internal pure returns (bool) {
        return tokenData & IS_GATEWAY_MASK == IS_GATEWAY_MASK;
    }

    function getSymbolLength(bytes32 tokenData) internal pure returns (uint256) {
        return uint256((tokenData & LENGTH_MASK) >> 248);
    }

    function getSymbol(bytes32 tokenData) internal pure returns (string memory symbol) {
        uint256 length = getSymbolLength(tokenData);
        symbol = new string(length);
        bytes32 stringData = tokenData << 8;
        assembly {
            mstore(add(symbol, 0x20), stringData)
        }
    }


    function createTokenData(address tokenAddress, bool native) internal pure returns (bytes32 tokenData) {
        tokenData = bytes32(uint256(uint160(tokenAddress)));
        if (native) tokenData |= IS_NATIVE_MASK;
    }


    error SymbolTooLong();
    function createGatewayTokenData(address tokenAddress, bool native, string memory symbol) internal pure returns (bytes32 tokenData) {
        tokenData = bytes32(uint256(uint160(tokenAddress))) | IS_GATEWAY_MASK;
        if (native) tokenData |= IS_NATIVE_MASK;
        uint256 length = bytes(symbol).length;
        if(length > 11) revert SymbolTooLong();

        tokenData |= bytes32(length) << 248;
        bytes32 symbolData = bytes32(bytes(symbol)) >> 8;
        tokenData |= symbolData;
    }
}
