// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import { AxelarExecutable } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/executables/AxelarExecutable.sol';
import { IAxelarGateway } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol';
import { IAxelarGasService } from '@axelar-network/axelar-cgp-solidity/contracts/interfaces/IAxelarGasService.sol';
import { IERC20 } from './interfaces/IERC20.sol';
import { IBurnableMintableCappedERC20 } from '@axelar-network/axelar-cgp-solidity/contracts/interfaces/IBurnableMintableCappedERC20.sol';
import { IMintableCappedERC20 } from '@axelar-network/axelar-cgp-solidity/contracts/interfaces/IMintableCappedERC20.sol';
import { BurnableMintableCappedERC20 } from '@axelar-network/axelar-cgp-solidity/contracts/BurnableMintableCappedERC20.sol';

import { ITokenLinker } from './interfaces/ITokenLinker.sol';
import { ITokenLinkerCallable } from './interfaces/ITokenLinkerCallable.sol';
import { IRemoteAddressValidator } from './interfaces/IRemoteAddressValidator.sol';
import { Upgradable } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/upgradables/Upgradable.sol';

import { LinkedTokenData } from './libraries/LinkedTokenData.sol';
import { AddressBytesUtils } from './libraries/AddressBytesUtils.sol';

contract TokenLinker is ITokenLinker, AxelarExecutable, Upgradable, ITokenLinkerCallable {
    using LinkedTokenData for bytes32;

    IAxelarGasService public immutable gasService;
    IRemoteAddressValidator public immutable remoteAddressValidator;
    // bytes32(uint256(keccak256('token-linker')) - 1)
    bytes32 public override constant contractId = 0x6ec6af55bf1e5f27006bfa01248d73e8894ba06f23f8002b047607ff2b1944ba;
    mapping(bytes32 => bytes32) public override tokenRegistry;
    mapping(bytes32 => string) public override originalChain;
    mapping(address => bytes32) public override tokenIds;
    bytes32 public immutable chainNameHash;
    enum RemoteActions {
        GIVE_TOKEN,
        GIVE_TOKEN_WITH_DATA,
        DEPLOY_TOKEN,
        SEND_TOKEN,
        SEND_TOKEN_WITH_DATA
    }

    constructor(
        address gatewayAddress_,
        address gasServiceAddress_,
        address remoteAddressValidatorAddress_,
        string memory chainName
    ) AxelarExecutable(gatewayAddress_) {
        if (gatewayAddress_ == address(0) || gasServiceAddress_ == address(0)) revert TokenLinkerZeroAddress();
        gasService = IAxelarGasService(gasServiceAddress_);
        remoteAddressValidator = IRemoteAddressValidator(remoteAddressValidatorAddress_);
        chainNameHash = keccak256(bytes(chainName));
    }

    function getTokenAddress(bytes32 tokenId) public view override returns (address) {
        return tokenRegistry[tokenId].getAddress();
    }

    function getNativeTokenId(address tokenAddress) public view override returns (bytes32) {
        return keccak256(abi.encode(chainNameHash, tokenAddress));
    }

    function registerToken(address tokenAddress) external override returns (bytes32 tokenId) {
        tokenId = getNativeTokenId(tokenAddress);
        if(tokenRegistry[tokenId] != bytes32(0)) revert AlreadyRegistered();
        _validateNativeToken(tokenAddress);
        tokenRegistry[tokenId] = LinkedTokenData.createTokenData(tokenAddress, true);
        tokenIds[tokenAddress] = tokenId;
    }

    function registerNativeGatewayToken(address tokenAddress) external override onlyOwner returns (bytes32 tokenId) {
        tokenId = getNativeTokenId(tokenAddress);
        (,string memory symbol,) = _validateNativeToken(tokenAddress);
        if(gateway.tokenAddresses(symbol) != tokenAddress) revert NotGatewayToken();
        tokenRegistry[tokenId] = LinkedTokenData.createGatewayTokenData(tokenAddress, true, symbol);
        tokenIds[tokenAddress] = tokenId;
    }

    function registerRemoteGatewayToken(address tokenAddress, bytes32 tokenId, string calldata origin) external override onlyOwner {
        (,string memory symbol,) = _validateNativeToken(tokenAddress);
        if(gateway.tokenAddresses(symbol) != tokenAddress) revert NotGatewayToken();
        tokenRegistry[tokenId] = LinkedTokenData.createGatewayTokenData(tokenAddress, true, symbol);
        tokenIds[tokenAddress] = tokenId;
        originalChain[tokenId] = origin;
    }

    function registerTokenAndDeployRemoteTokens(address tokenAddress, string[] calldata destinationChains)
        external
        payable
        override
        returns (bytes32 tokenId)
    {
        tokenId = getNativeTokenId(tokenAddress);
        if(tokenRegistry[tokenId] != bytes32(0)) revert AlreadyRegistered();
        tokenRegistry[tokenId] = LinkedTokenData.createTokenData(tokenAddress, true);
        tokenIds[tokenAddress] = tokenId;
        uint256 length = destinationChains.length;
        (string memory name, string memory symbol, uint8 decimals) = _validateNativeToken(tokenAddress);
        for (uint256 i; i < length; ++i) {
            _deployRemoteToken(tokenId, name, symbol, decimals, destinationChains[i]);
        }
    }

    function deployRemoteTokens(bytes32 tokenId, string[] calldata destinationChains) external payable override {
        bytes32 tokenData = tokenRegistry[tokenId];
        if (!tokenData.isNative()) revert NotNativeToken();
        address tokenAddress = tokenData.getAddress();

        (string memory name, string memory symbol, uint8 decimals) = _validateNativeToken(tokenAddress);

        uint256 length = destinationChains.length;
        for (uint256 i; i < length; ++i) {
            _deployRemoteToken(tokenId, name, symbol, decimals, destinationChains[i]);
        }
    }

    function _deployRemoteToken(
        bytes32 tokenId,
        string memory name,
        string memory symbol,
        uint8 decimals,
        string calldata destinationChain
    ) internal {
        bytes memory payload = abi.encode(RemoteActions.DEPLOY_TOKEN, tokenId, name, symbol, decimals);
        _sendPayload(destinationChain, payload);
    }

    function _validateNativeToken(address tokenAddress)
        internal
        returns (
            string memory name,
            string memory symbol,
            uint8 decimals
        )
    {
        IERC20 token = IERC20(tokenAddress);
        name = token.name();
        symbol = token.symbol();
        decimals = token.decimals();
    }

    function _deployToken(
        bytes32 tokenId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals
    ) internal {
        if(tokenRegistry[tokenId] != bytes32(0)) revert AlreadyRegistered();
        address tokenAddress = address(new BurnableMintableCappedERC20(tokenName, tokenSymbol, decimals, 0));
        tokenRegistry[tokenId] = LinkedTokenData.createTokenData(tokenAddress, false);
        tokenIds[tokenAddress] = tokenId;
    }

    function sendToken(
        bytes32 tokenId,
        string calldata destinationChain,
        bytes calldata to,
        uint256 amount
    ) external payable override {
        bytes32 tokenData = tokenRegistry[tokenId];
        _takeToken(tokenData, msg.sender, amount);
        emit Sending(destinationChain, to, amount);
        if(tokenData.isGateway()) {
            bytes memory payload = abi.encode(RemoteActions.GIVE_TOKEN, tokenId, to);
            _callContractWithToken(destinationChain, tokenData, amount, payload);
        } else {
            bytes memory payload = abi.encode(RemoteActions.GIVE_TOKEN, tokenId, to, amount);
            _sendPayload(destinationChain, payload);
        }
    }

    function sendTokenWithData(
        bytes32 tokenId,
        string calldata destinationChain,
        bytes calldata to,
        uint256 amount,
        bytes calldata data
    ) external payable override {
        bytes32 tokenData = tokenRegistry[tokenId];
        _takeToken(tokenData, msg.sender, amount);
        emit SendingWithData(destinationChain, to, amount, msg.sender, data);
        if(tokenData.isGateway()) {
            bytes memory payload = abi.encode(RemoteActions.GIVE_TOKEN_WITH_DATA, tokenId, to, abi.encodePacked(msg.sender), data);
            _callContractWithToken(destinationChain, tokenData, amount, payload);
        } else {
            bytes memory payload = abi.encode(RemoteActions.GIVE_TOKEN_WITH_DATA, tokenId, to, amount, abi.encodePacked(msg.sender), data);
            _sendPayload(destinationChain, payload);
        }
    }

    function _sendPayload(string memory destinationChain, bytes memory payload) internal {
        string memory destinationAddress = remoteAddressValidator.getRemoteAddress(destinationChain);
        uint256 gasValue = msg.value;
        if (gasValue > 0) {
            gasService.payNativeGasForContractCall{ value: gasValue }(
                address(this),
                destinationChain,
                destinationAddress,
                payload,
                msg.sender
            );
        }
        gateway.callContract(destinationChain, destinationAddress, payload);
    }

    function _callContractWithToken(string calldata destinationChain, bytes32 tokenData, uint256 amount, bytes memory payload) internal {
        string memory destinationAddress = remoteAddressValidator.getRemoteAddress(destinationChain);
        uint256 gasValue = msg.value;
        string memory symbol = tokenData.getSymbol();
        if (gasValue > 0) {
            gasService.payNativeGasForContractCallWithToken{ value: gasValue }(
                address(this),
                destinationChain,
                destinationAddress,
                payload,
                symbol,
                amount,
                msg.sender
            );
        }
        IERC20(tokenData.getAddress()).approve(address(gateway), amount);
        gateway.callContractWithToken(destinationChain, destinationAddress, payload, symbol, amount);
    }

    function _execute(
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) internal override {
        if (!remoteAddressValidator.validateSender(sourceChain, sourceAddress)) return;
        RemoteActions action = abi.decode(payload, (RemoteActions));
        if (action == RemoteActions.DEPLOY_TOKEN) {
            bytes32 tokenId;
            string memory tokenName;
            string memory tokenSymbol;
            uint8 decimals;
            (, tokenId, tokenName, tokenSymbol, decimals) = abi.decode(payload, (RemoteActions, bytes32, string, string, uint8));
            _deployToken(tokenId, tokenName, tokenSymbol, decimals);
        } else if (action == RemoteActions.GIVE_TOKEN) {
            bytes32 tokenId;
            bytes memory to;
            uint256 amount;
            (, tokenId, to, amount) = abi.decode(payload, (RemoteActions, bytes32, bytes, uint256));
            _giveToken(tokenId, AddressBytesUtils.toAddress(to), amount);
        } else if (action == RemoteActions.GIVE_TOKEN_WITH_DATA) {
            bytes32 tokenId;
            bytes memory to;
            uint256 amount;
            bytes memory from;
            bytes memory data;
            (, tokenId, to, amount, from, data) = abi.decode(payload, (RemoteActions, bytes32, bytes, uint256, bytes, bytes));
            _giveTokenWithData(tokenId, AddressBytesUtils.toAddress(to), amount, sourceChain, from, data);
        }
    }

    function _executeWithToken(
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload,
        string calldata /*symbol*/,
        uint256 amount
    ) internal override {
        if (!remoteAddressValidator.validateSender(sourceChain, sourceAddress)) return;   
        
        RemoteActions action = abi.decode(payload, (RemoteActions));
        
        if (action == RemoteActions.GIVE_TOKEN) {
            (, bytes32 tokenId, bytes memory to) = abi.decode(payload, (RemoteActions, bytes32, bytes));
            bytes32 tokenData = tokenRegistry[tokenId];
            address tokenAddress = tokenData.getAddress();
            _transfer(tokenAddress, AddressBytesUtils.toAddress(to), amount);
        } else if (action == RemoteActions.GIVE_TOKEN_WITH_DATA) {
            _giveTokenWithDataWrapper(payload, amount, sourceChain);
        }
    }

    function _giveTokenWithDataWrapper(bytes calldata payload, uint256 amount, string calldata sourceChain) internal {
            (, bytes32 tokenId, bytes memory toBytes, bytes memory sourceAddress ,bytes memory data) = abi.decode(payload, (RemoteActions, bytes32, bytes, bytes, bytes));
            address to = AddressBytesUtils.toAddress(toBytes);
            bytes32 tokenData = tokenRegistry[tokenId];
            address tokenAddress = tokenData.getAddress();
            _transfer(tokenAddress, to, amount);
            ITokenLinkerCallable(to).processToken(tokenAddress, sourceChain, sourceAddress, amount, data);
    }

    function _transfer(
        address tokenAddress,
        address to,
        uint256 amount
    ) internal {
        (bool success, bytes memory returnData) = tokenAddress.call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        bool transferred = success && (returnData.length == uint256(0) || abi.decode(returnData, (bool)));

        if (!transferred || tokenAddress.code.length == 0) revert TransferFailed();
    }

    function _transferFrom(
        address tokenAddress,
        address from,
        uint256 amount
    ) internal {
        (bool success, bytes memory returnData) = tokenAddress.call(
            abi.encodeWithSelector(IERC20.transferFrom.selector, from, address(this), amount)
        );
        bool transferred = success && (returnData.length == uint256(0) || abi.decode(returnData, (bool)));

        if (!transferred || tokenAddress.code.length == 0) revert TransferFromFailed();
    }

    function _mint(
        address tokenAddress,
        address to,
        uint256 amount
    ) internal {
        (bool success, ) = tokenAddress.call(abi.encodeWithSelector(IMintableCappedERC20.mint.selector, to, amount));

        if (!success || tokenAddress.code.length == 0) revert MintFailed();
    }

    function _burn(
        address tokenAddress,
        address from,
        uint256 amount
    ) internal {
        (bool success, ) = tokenAddress.call(abi.encodeWithSelector(IBurnableMintableCappedERC20.burnFrom.selector, from, amount));

        if (!success || tokenAddress.code.length == 0) revert BurnFailed();
    }

    function _giveToken(
        bytes32 tokenId,
        address to,
        uint256 amount
    ) internal {
        bytes32 tokenData = tokenRegistry[tokenId];
        address tokenAddress = tokenData.getAddress();
        if (tokenData.isNative()) {
            _transfer(tokenAddress, to, amount);
        } else {
            _mint(tokenAddress, to, amount);
        }
    }

    function _takeToken(
        bytes32 tokenData,
        address to,
        uint256 amount
    ) internal {
        address tokenAddress = tokenData.getAddress();
        if (tokenData.isNative()) {
            _transferFrom(tokenAddress, to, amount);
        } else {
            _burn(tokenAddress, to, amount);
        }
    }

    function _giveTokenWithData(
        bytes32 tokenId,
        address to,
        uint256 amount,
        string calldata sourceChain,
        bytes memory sourceAddress,
        bytes memory data
    ) internal {
        bytes32 tokenData = tokenRegistry[tokenId];
        address tokenAddress = tokenData.getAddress();
        if (tokenData.isNative()) {
            _transfer(tokenAddress, to, amount);
        } else {
            _mint(tokenAddress, to, amount);
        }
        ITokenLinkerCallable(to).processToken(tokenAddress, sourceChain, sourceAddress, amount, data);
    }


    // This is meant to send gateway tokens to chains where the gateway tokens are not supported.
    // To do so, fist a user would call sendTokenWithData, sending the gateway tokens to the chain where the token is native
    // The destination would be the token linker in that chain, and the data tell the token linker where to send the tokens
    // There is one issue however, that needs to be handled by microservices: This second contract call cannot have gas payed by microservices
    function processToken(
        address tokenAddress,
        string calldata /*sourceChain*/,
        bytes calldata sourceAddress,
        uint256 amount,
        bytes calldata data
    ) external override {
        (
            RemoteActions action,
            string memory destinationChain,
            bytes memory to
        ) = abi.decode(data, (RemoteActions, string, bytes));
        bytes32 tokenId = tokenIds[tokenAddress];
        bytes memory payload;
        if(action == RemoteActions.SEND_TOKEN) {
            payload = abi.encode(RemoteActions.GIVE_TOKEN, tokenId, to, amount);
        } else if(action == RemoteActions.SEND_TOKEN_WITH_DATA) {
            (, , , bytes memory data2) = abi.decode(data, (RemoteActions, string, bytes, bytes));
            payload = abi.encode(RemoteActions.GIVE_TOKEN, tokenId, to, amount, sourceAddress, data2);
        }
        _sendPayload(destinationChain, payload);
    }
}
