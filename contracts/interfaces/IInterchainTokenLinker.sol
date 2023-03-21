// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import { ITokenDeployer } from './ITokenDeployer.sol';

interface IInterchainTokenLinker {
    error TokenLinkerZeroAddress();
    error TransferFailed();
    error TransferFromFailed();
    error MintFailed();
    error BurnFailed();
    error NotOriginToken();
    error AlreadyRegistered();
    error NotGatewayToken();
    error GatewayToken();
    error LengthMismatch();
    error NotSelf();
    error ExecutionFailed();
    error ExceedMintLimit(bytes32 tokenId);
    error TokenDeploymentFailed();

    event Sending(string destinationChain, bytes destinationAddress, uint256 indexed amount);
    event SendingWithData(string destinationChain, bytes destinationAddress, uint256 indexed amount, address indexed from, bytes data);
    event Receiving(string sourceChain, address indexed destinationAddress, uint256 indexed amount);
    event ReceivingWithData(
        string sourceChain,
        address indexed destinationAddress,
        uint256 indexed amount,
        address indexed from,
        bytes data
    );
    event TokenRegistered(bytes32 indexed tokenId, address indexed tokenAddress, bool native, bool gateway, bool remoteGateway);
    event TokenDeployed(address indexed tokenAddress, string name, string symbol, uint8 decimals, address indexed owner);
    event RemoteTokenRegisterInitialized(bytes32 indexed tokenId, string destinationChain, uint256 gasValue);

    function chainNameHash() external view returns (bytes32);

    function getTokenData(bytes32 tokenId) external view returns (bytes32 tokenData);

    function getOriginalChain(bytes32 tokenId) external view returns (string memory origin);

    function getTokenId(address tokenAddress) external view returns (bytes32 tokenId);

    function getTokenMintLimit(bytes32 tokenId) external view returns (uint256 mintLimit);

    function getTokenMintAmount(bytes32 tokenId) external view returns (uint256 amount);

    function tokenDeployer() external view returns (ITokenDeployer);

    function getTokenAddress(bytes32 tokenId) external view returns (address tokenAddress);

    function getOriginTokenId(address tokenAddress) external view returns (bytes32 tokenId);

    function deployInterchainToken(
        string calldata tokenName,
        string calldata tokenSymbol,
        uint8 decimals,
        address owner,
        bytes32 salt,
        string[] calldata destinationChains,
        uint256[] calldata gasValues
    ) external payable;

    function registerOriginToken(address tokenAddress) external returns (bytes32 tokenId);

    function registerOriginTokenAndDeployRemoteTokens(
        address tokenAddress,
        string[] calldata destinationChains,
        uint256[] calldata gasValues
    ) external payable returns (bytes32 tokenId);

    function deployRemoteTokens(bytes32 tokenId, string[] calldata destinationChains, uint256[] calldata gasValues) external payable;

    function setTokenMintLimit(bytes32 tokenId, uint256 mintLimit) external;

    function sendToken(bytes32 tokenId, string memory destinationChain, bytes memory to, uint256 amount) external payable;

    function callContractWithInterToken(
        bytes32 tokenId,
        string memory destinationChain,
        bytes memory to,
        uint256 amount,
        bytes calldata data
    ) external payable;

    function registerOriginGatewayToken(string calldata symbol) external returns (bytes32 tokenId);

    function registerRemoteGatewayToken(string calldata symbol, bytes32 tokenId, string calldata origin) external;

    function selfDeployToken(
        bytes32 tokenId,
        string memory origin,
        string calldata tokenName,
        string calldata tokenSymbol,
        uint8 decimals,
        bool isGateway
    ) external;

    function selfGiveToken(bytes32 tokenId, bytes calldata destinationAddress, uint256 amount) external;

    function selfGiveTokenWithData(
        bytes32 tokenId,
        string calldata sourceChain,
        bytes calldata sourceAddress,
        bytes calldata destinationAddress,
        uint256 amount,
        bytes calldata data
    ) external;

    function selfSendToken(bytes32 tokenId, string calldata destinationChain, bytes calldata destinationAddress, uint256 amount) external;

    function selfSendTokenWithData(
        bytes32 tokenId,
        string calldata sourceChain,
        bytes calldata sourceAddress,
        string calldata destinationChain,
        bytes calldata destinationAddress,
        uint256 amount,
        bytes calldata data
    ) external;
}
