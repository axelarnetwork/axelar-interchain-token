// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import { AxelarExecutable } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/executables/AxelarExecutable.sol';
import { IAxelarGateway } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol';
import { IAxelarGasService } from '@axelar-network/axelar-cgp-solidity/contracts/interfaces/IAxelarGasService.sol';
import { IERC20 } from './interfaces/IERC20.sol';
import { IBurnableMintableCappedERC20 } from '@axelar-network/axelar-cgp-solidity/contracts/interfaces/IBurnableMintableCappedERC20.sol';
import { IMintableCappedERC20 } from '@axelar-network/axelar-cgp-solidity/contracts/interfaces/IMintableCappedERC20.sol';

import { IInterchainTokenLinker } from './interfaces/IInterchainTokenLinker.sol';
import { IInterTokenExecutable } from './interfaces/IInterTokenExecutable.sol';
import { ILinkerRouter } from './interfaces/ILinkerRouter.sol';
import { ITokenDeployer } from './interfaces/ITokenDeployer.sol';
import { Upgradable } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/upgradables/Upgradable.sol';

import { LinkedTokenData } from './libraries/LinkedTokenData.sol';
import { AddressBytesUtils } from './libraries/AddressBytesUtils.sol';

contract InterchainTokenLinker is IInterchainTokenLinker, AxelarExecutable, Upgradable {
    using LinkedTokenData for bytes32;

    IAxelarGasService public immutable gasService;
    ILinkerRouter public immutable linkerRouter;
    ITokenDeployer public immutable tokenDeployer;
    // bytes32(uint256(keccak256('token-linker')) - 1)
    bytes32 public constant contractId = 0x6ec6af55bf1e5f27006bfa01248d73e8894ba06f23f8002b047607ff2b1944ba;
    mapping(bytes32 => bytes32) public tokenDatas;
    mapping(bytes32 => string) public originalChain;
    mapping(address => bytes32) public tokenIds;
    //bytes32 public immutable chainNameHash;
    string chainName;

    constructor(
        address gatewayAddress_,
        address gasServiceAddress_,
        address linkerRouterAddress_,
        address tokenDeployerAddress_,
        string memory chainName_
    ) AxelarExecutable(gatewayAddress_) {
        if (gatewayAddress_ == address(0) 
            || gasServiceAddress_ == address(0) 
            || linkerRouterAddress_ == address(0)
        ) revert TokenLinkerZeroAddress();
        gasService = IAxelarGasService(gasServiceAddress_);
        linkerRouter = ILinkerRouter(linkerRouterAddress_);
        tokenDeployer = ITokenDeployer(tokenDeployerAddress_);
        chainName = chainName_;
        //chainNameHash = keccak256(bytes(chainName_));
    }

    modifier onlySelf() {
        if(msg.sender != address(this)) revert NotSelf();
        _;
    }

    /* GETTERS */

    function getTokenAddress(bytes32 tokenId) public view returns (address) {
        return tokenDatas[tokenId].getAddress();
    }

    function getOriginTokenId(address tokenAddress) public pure returns (bytes32) {
        return keccak256(abi.encode(tokenAddress));
    }

    /* REGISTER AND DEPLOY TOKENS */
    
    function registerOriginToken(address tokenAddress) external returns (bytes32 tokenId) {
        (, string memory symbol,) = _validateOriginToken(tokenAddress);
        if(gateway.tokenAddresses(symbol) == tokenAddress) revert GatewayToken(); 
        (tokenId,) = _registerToken(tokenAddress);
    }

    function registerOriginGatewayToken(string calldata symbol) external onlyOwner returns (bytes32 tokenId) {
        address tokenAddress = gateway.tokenAddresses(symbol);
        if(tokenAddress == address(0)) revert NotGatewayToken();
        tokenId = getOriginTokenId(tokenAddress);
        tokenDatas[tokenId] = LinkedTokenData.createGatewayTokenData(tokenAddress, true, symbol);
        tokenIds[tokenAddress] = tokenId;
    }

    function registerRemoteGatewayToken(string calldata symbol, bytes32 tokenId, string calldata origin) external onlyOwner {
        address tokenAddress = gateway.tokenAddresses(symbol);
        if(tokenAddress == address(0)) revert NotGatewayToken();
        tokenDatas[tokenId] = LinkedTokenData.createGatewayTokenData(tokenAddress, false, symbol);
        tokenIds[tokenAddress] = tokenId;
        originalChain[tokenId] = origin;
    }
        
    function registerOriginTokenAndDeployRemoteTokens(
        address tokenAddress, 
        string[] calldata destinationChains, 
        uint256[] calldata gasValues
    ) external payable override returns (bytes32 tokenId) {
        bytes32 tokenData;
        (tokenId, tokenData) = _registerToken(tokenAddress);
        string memory symbol = _deployRemoteTokens(destinationChains, gasValues, tokenId, tokenData);
        if(gateway.tokenAddresses(symbol) == tokenAddress) revert GatewayToken(); 
    }
        
    function deployRemoteTokens(bytes32 tokenId, string[] calldata destinationChains, uint256[] calldata gasValues) external payable {
        bytes32 tokenData = tokenDatas[tokenId];
        if (!tokenData.isOrigin()) revert NotOriginToken();
        _deployRemoteTokens(destinationChains, gasValues, tokenId, tokenData);
    }

    /* SEND TOKENS */

    function sendToken(
        bytes32 tokenId,
        string calldata destinationChain,
        bytes calldata destinationAddress,
        uint256 amount
    ) external payable {
        _takeToken(tokenId, msg.sender, amount);
        _sendToken(tokenId, destinationChain, destinationAddress, amount);
    }

    function callContractWithInterToken(
        bytes32 tokenId,
        string calldata destinationChain,
        bytes calldata destinationAddress,
        uint256 amount,
        bytes calldata data
    ) external payable {
        _takeToken(tokenId, msg.sender, amount);
        _sendTokenWithData(tokenId, chainName, AddressBytesUtils.toBytes(msg.sender), destinationChain, destinationAddress, amount, data);
    }

    /* EXECUTE AND EXECUTE WITH TOKEN */

    function _execute(
        string calldata sourceChain,
        string calldata sourceAddress, 
        bytes calldata payload
    ) internal override {
        if (!linkerRouter.validateSender(sourceChain, sourceAddress)) return;
        (bool success,) = address(this).call(payload);
        if(!success) revert ExecutionFailed();
    }

    function _executeWithToken(
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload,
        string calldata /*symbol*/,
        uint256 /*amount*/
    ) internal override {
        if (!linkerRouter.validateSender(sourceChain, sourceAddress)) return;  
        (bool success,) = address(this).call(payload);
        if(!success) revert ExecutionFailed();
    }

    /* ONLY SELF FUNCTIONS */

    function selfDeployToken(
        bytes32 tokenId,
        string calldata origin,
        string calldata tokenName,
        string calldata tokenSymbol,
        uint8 decimals,
        bool isGateway
    ) public onlySelf {
        bytes32 tokenData = tokenDatas[tokenId];
        if(tokenData != bytes32(0)) {
            if(isGateway && !tokenData.isGateway()) {
                tokenDatas[tokenId] = LinkedTokenData.createRemoteGatewayTokenData(tokenData.getAddress());
                return;
            }
            revert AlreadyRegistered();
        }
        address tokenAddress = tokenDeployer.deployToken(tokenName, tokenSymbol, decimals, tokenId);
        if(isGateway) {
            tokenDatas[tokenId] = LinkedTokenData.createRemoteGatewayTokenData(tokenAddress);
        } else {
            tokenDatas[tokenId] = LinkedTokenData.createTokenData(tokenAddress, false);
        }
        tokenIds[tokenAddress] = tokenId;
        originalChain[tokenId] = origin;
    }

    function selfGiveToken(
        bytes32 tokenId, 
        bytes calldata destinationAddress,
        uint256 amount
    ) public onlySelf {
        _giveToken(tokenId, AddressBytesUtils.toAddress(destinationAddress), amount);
    }

    function selfGiveTokenWithData(
        bytes32 tokenId,
        string calldata sourceChain, 
        bytes calldata sourceAddress, 
        bytes calldata destinationAddress,
        uint256 amount,
        bytes memory data
    ) public onlySelf {
        _giveTokenWithData(tokenId, AddressBytesUtils.toAddress(destinationAddress), amount, sourceChain, sourceAddress, data);
    }

    function selfSendToken(
        bytes32 tokenId,
        string calldata destinationChain,
        bytes calldata destinationAddress,
        uint256 amount
    ) public onlySelf {
        _sendToken(tokenId, destinationChain, destinationAddress, amount);
    }

    function selfSendTokenWithData(
        bytes32 tokenId, 
        string calldata sourceChain,
        bytes calldata sourceAddress,
        string calldata destinationChain, 
        bytes calldata destinationAddress,
        uint256 amount,
        bytes calldata data
    ) public onlySelf {
        _sendTokenWithData(tokenId, sourceChain, sourceAddress, destinationChain, destinationAddress, amount, data);
    }

    /* HELPER FUNCTIONS */

    function _registerToken(address tokenAddress) internal returns (bytes32 tokenId, bytes32 tokenData) {
        if(tokenIds[tokenAddress] != bytes32(0)) revert AlreadyRegistered();
        tokenId = getOriginTokenId(tokenAddress);
        if(tokenDatas[tokenId] != bytes32(0)) revert AlreadyRegistered();
        tokenData = LinkedTokenData.createTokenData(tokenAddress, true);
        tokenDatas[tokenId] = tokenData;
        tokenIds[tokenAddress] = tokenId;
    }

    function _deployRemoteTokens(
        string[] calldata destinationChains, 
        uint256[] calldata gasValues,
        bytes32 tokenId,
        bytes32 tokenData
    ) internal returns (string memory) {
        (string memory name, string memory symbol, uint8 decimals) = _validateOriginToken(tokenData.getAddress());
        uint256 length = destinationChains.length;
        if( gasValues.length != length) revert LengthMismatch();
        for (uint256 i; i < length; ++i) {
            if(tokenData.isGateway() && linkerRouter.supportedByGateway(destinationChains[i])) revert SupportedByGateway();
            bytes memory payload = abi.encodeWithSelector(
                this.selfDeployToken.selector, tokenId, chainName, name, symbol, decimals, tokenData.isGateway()
            );
            _callContract(destinationChains[i], payload, gasValues[i]);
        }
        return symbol;
    }

    function _validateOriginToken(address tokenAddress)
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

    function _sendToken(
        bytes32 tokenId,
        string calldata destinationChain,
        bytes calldata to,
        uint256 amount
    ) internal {
        bytes32 tokenData = tokenDatas[tokenId];
        bytes memory payload;
        if(tokenData.isGateway()) {
            if(linkerRouter.supportedByGateway(destinationChain)) {
                payload = abi.encodeWithSelector(this.selfGiveToken.selector, tokenId, to, amount);
               _callContractWithToken(destinationChain, tokenData, amount, payload);
            } else if(tokenData.isOrigin()) {
                payload = abi.encodeWithSelector(this.selfGiveToken.selector, tokenId, to, amount);
               _callContract(destinationChain, payload, msg.value);
            } else {
                payload = abi.encodeWithSelector(this.selfSendToken.selector, tokenId, destinationChain, to, amount);
               _callContractWithToken(originalChain[tokenId], tokenData, amount, payload);
            }
        } else if (tokenData.isRemoteGateway()) {
            if(keccak256(bytes(destinationChain)) == keccak256(bytes(originalChain[tokenId]))) {
                payload = abi.encodeWithSelector(this.selfGiveToken.selector, tokenId, to, amount);
               _callContract(destinationChain, payload, msg.value);
            } else {
                payload = abi.encodeWithSelector(this.selfSendToken.selector, tokenId, destinationChain, to, amount);
               _callContract(originalChain[tokenId], payload, msg.value);
            }
        } else {
                payload = abi.encodeWithSelector(this.selfGiveToken.selector, tokenId, to, amount);
               _callContract(destinationChain, payload, msg.value);
        }
    }

    function _sendTokenWithData(
        bytes32 tokenId,
        string memory sourceChain,
        bytes memory sourceAddress,
        string calldata destinationChain,
        bytes calldata to,
        uint256 amount,
        bytes calldata data
    ) internal {
        bytes32 tokenData = tokenDatas[tokenId];
        bytes memory payload;
        if(tokenData.isGateway()) {
            if(linkerRouter.supportedByGateway(destinationChain)) {
                payload = abi.encodeWithSelector(this.selfGiveTokenWithData.selector, tokenId, sourceChain, sourceAddress, to, amount, data);
               _callContractWithToken(destinationChain, tokenData, amount, payload);
            } else if(tokenData.isOrigin()) {
                payload = abi.encodeWithSelector(this.selfGiveTokenWithData.selector, tokenId, sourceChain, sourceAddress, to, amount, data);
               _callContract(destinationChain, payload, msg.value);
            } else {
                payload = abi.encodeWithSelector(this.selfSendTokenWithData.selector, tokenId, sourceChain, sourceAddress, destinationChain, to, amount, data);
               _callContractWithToken(originalChain[tokenId], tokenData, amount, payload);
            }
        } else if (tokenData.isRemoteGateway()) {
            if(keccak256(bytes(destinationChain)) == keccak256(bytes(originalChain[tokenId]))) { 
                payload = abi.encodeWithSelector(this.selfGiveTokenWithData.selector, tokenId, sourceChain, sourceAddress, to, amount, data);
               _callContract(destinationChain, payload, msg.value);
            } else {
                payload = abi.encodeWithSelector(this.selfSendTokenWithData.selector, tokenId, sourceChain, sourceAddress, destinationChain, to, amount, data);
               _callContract(originalChain[tokenId], payload, msg.value);
            }
        } else {
                payload = abi.encodeWithSelector(this.selfGiveTokenWithData.selector, tokenId, sourceChain, sourceAddress, to, amount, data);
               _callContract(destinationChain, payload, msg.value);
        }
    }

    function _callContract(string memory destinationChain, bytes memory payload, uint256 gasValue) internal {
        string memory destinationAddress = linkerRouter.getRemoteAddress(destinationChain);
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

    function _callContractWithToken(
        string memory destinationChain, 
        bytes32 tokenData, 
        uint256 amount, 
        bytes memory payload
    ) internal {
        string memory destinationAddress = linkerRouter.getRemoteAddress(destinationChain);
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
        bytes32 tokenData = tokenDatas[tokenId];
        address tokenAddress = tokenData.getAddress();
        if (tokenData.isOrigin() || tokenData.isGateway()) {
            _transfer(tokenAddress, to, amount);
        } else {
            _mint(tokenAddress, to, amount);
        }
    }

    function _takeToken(
        bytes32 tokenId,
        address from,
        uint256 amount
    ) internal {
        bytes32 tokenData = tokenDatas[tokenId];
        address tokenAddress = tokenData.getAddress();
        if (tokenData.isOrigin() || tokenData.isGateway()) {
            _transferFrom(tokenAddress, from, amount);
        } else {
            _burn(tokenAddress, from, amount);
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
        bytes32 tokenData = tokenDatas[tokenId];
        address tokenAddress = tokenData.getAddress();
        if (tokenData.isOrigin() || tokenData.isGateway()) {
            _transfer(tokenAddress, to, amount);
        } else {
            _mint(tokenAddress, to, amount);
        }
        IInterTokenExecutable(to).exectuteWithInterToken(tokenAddress, sourceChain, sourceAddress, amount, data);
    }
}
