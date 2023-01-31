// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

interface ITokenLinker {
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

    event Sending(string destinationChain, bytes destinationAddress, uint256 indexed amount);
    event SendingWithData(
        string destinationChain,
        bytes destinationAddress,
        uint256 indexed amount,
        address indexed from,
        bytes data
    );
    event Receiving(string sourceChain, address indexed destinationAddress, uint256 indexed amount);
    event ReceivingWithData(
        string sourceChain,
        address indexed destinationAddress,
        uint256 indexed amount,
        address indexed from,
        bytes data
    );

    function tokenDatas(bytes32 tokenId) external view returns (bytes32 tokenData);
    function originalChain(bytes32 tokenId) external view returns (string memory origin);
    function tokenIds(address tokenAddress) external view returns (bytes32 tokenId);

    function getTokenAddress(bytes32 tokenId) external view returns (address tokenAddress);

    function getOriginTokenId(address tokenAddress) external view returns (bytes32 tokenId);

    function registerOriginToken(address tokenAddress) external returns (bytes32 tokenId);

    function registerOriginTokenAndDeployRemoteTokens(address tokenAddress, string[] calldata destinationChains, uint256[] calldata gasValues)
        external
        payable
        returns (bytes32 tokenId);

    function deployRemoteTokens(bytes32 tokenId, string[] calldata destinationChains, uint256[] calldata gasValues) external payable;

    function sendToken(
        bytes32 tokenId,
        string memory destinationChain,
        bytes memory to,
        uint256 amount
    ) external payable;

    function sendTokenWithData(
        bytes32 tokenId,
        string memory destinationChain,
        bytes memory to,
        uint256 amount,
        bytes calldata data
    ) external payable;

    function registerOriginGatewayToken(string calldata symbol) external returns (bytes32 tokenId);
    function registerRemoteGatewayToken(string calldata symbol, bytes32 tokenId, string calldata origin) external;
}
