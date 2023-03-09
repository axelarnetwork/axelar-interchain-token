# Axelar Interchain Token

This project (previously known as Token Linker) aims to allow anyone to permissionlessly take any tokens cross-chain. We aim to have a front to allow for easy use of the smart contracts to anyone.

## Architecture

The design for EVM chains is layed out here. We aim to include compatible smart contracts on other chains once the infastructure needed is availabe.

There are four smart contracts on each chain: The `InterchainTokenLinker`, `LinkerRouter`, `BytecodeServer` and `TokenDeployer`. Thorought this documentation we refer to 'native' tokens to describe `ERC20` tokens that exist on a chain natively. Anyone can register native tokens on a chain and have 'mirrored' (also referred to as remote) tokens deployed on any other chain. These mirrored tokens have a one-to-one relationship with the native tokens because anyone can send some native tokens to the `InterchainTokenLinker` on a chain to receive the same amount of mirrored tokens, or vice versa. The token linker will lock the native tokens on the native chain to mint mirrored tokens on any other chain, or it will burn tokens on any chain to unlock tokens on the native chain.

The messaging of between `InterchainTokenLinker` contracts is done through GMP, and then to know
- where to send messages to and
- where to trust messages from
an `InterchainTokenLinker` will ask the `LinkerRouter` contract. The plan is to eventally have a non upgradable implementation for the `InterchainTokenLinker` while maintaining the ability to add new addresses in new chains in the `LinkerRouter`

## Smart Contracts

This section will be separated into two sections: the admin section, that explains the functions that admins can use, and the user section that explain the rest.

### Admin functions

#### Token Linker

- `registerNativeGatewayToken(address tokenAddress)`: Registers a preexisting native gateway token.
- `registerRemoteGatewayToken(address tokenAddress, bytes32 tokenId, string calldata origin)`: Registers a preexisting remote gateway token.

#### Remote Address Validator

- `addTrustedAddress(string calldata sourceChain, string calldata sourceAddress)`: adds a trusted address on a chain, or overwrites an existing trusted address.
- `removeTrustedAddress(string calldata sourceChain)`: removes a trusted address for a chain.

### User functions

All of the below are for the `InterchainTokenLinker`.

- `registerToken(address tokenAddress)`: Registers origin token at address `tokenAddress`.
- `deployRemoteTokens(tokenId, destinationChains, gasValues)`: Deploys a registered native token to the `destinationChains`
- `function registerOriginTokenAndDeployRemoteTokens(tokenAddress, destinationChains, gasValues)`: Combines the two above into a single function.

### TokenDeployer and BytecodeServer

In order to get the same address with different initialization parameters for out deployed tokens we want to use the `create3Deployer`. In order to do so we need to have the deployment bytecode on the blockchain and be able to modify the deployment arguments. This is why we deploy the `BytecodeServer` contract first that has the contract bytecode *without* the arguments, and then the `TokenDeployer` contract loads that bytecode and appends the constructor arguments at the end, before deploying. 