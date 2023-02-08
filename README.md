# Axelar Interchain Token

This project (previously known as Token Linker) aims to allow anyone to permissionlessly take any tokens cross-chain. We aim to have a front to allow for easy use of the smart contracts to anyone.

## Architecture

The design for EVM chains is layed out here. We aim to include compatible smart contracts on other chains once the infastructure needed is availabe.

There are two smart contracts on each chain: The `TokenLinker` contract and the `RemoteAddressValidator`. Thorought this documentation we refer to 'native' tokens to describe `ERC20` tokens that exist on a chain natively. Anyone can register native tokens on a chain and have 'mirrored' (also referred to as remote) tokens deployed on any other chain. These mirrored tokens have a one-to-one relationship with the native tokens because anyone can send some native tokens to the `tokenLinker` on a chain to receive the same amount of mirrored tokens, or vice versa. The token linker will lock the native tokens on the native chain to mint mirrored tokens on any other chain, or it will burn tokens on any chain to unlock tokens on the native chain.

The messaging of between `TokenLinker` contracts is done through GMP, and the to know
- where to send messages to and
- where to trust messages from
a `TokenLinker` will ask the `RemoteAddressValidator` contract. The plan is to eventally have a non upgradable implementation for the token linker while maintaining the ability to add new addresses in new chains in the `RemoteAddressValidator`

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

All of the below are for the `TokenLinker`.

- `registerToken(address tokenAddress)`

## Encoding

### Call Contract Payloads

There are currently five different payloads that can be sent via call contract. These payloads will always start with the first 32 bytes containing the `RemoteAction` that should occur. The encoding after will depend on the type of action required.

- `DEPLOY_TOKEN`: `(bytes32 tokenId, string name, string symbol, uint8 decimals, bool isGateway`. The first four are self explenatory, the last tells the remote chain whether the token should be marked
- `GIVE_TOKEN`:
- `GIVE_TOKEN_WITH_DATA`:
- `SEND_TOKEN`:
- `SEND_TOKEN_WITH_DATA`:

### Call Contract With Token Payloads