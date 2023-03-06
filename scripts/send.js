const { Contract, getDefaultProvider, constants: { AddressZero } } = require("ethers");
const ITokenLinker = require('../artifacts/contracts/interfaces/IInterchainTokenLinker.sol/IInterchainTokenLinker.json');

async function sendToken(chain, wallet, tokenId, destinationChain, destinationAddress, amount) {
    const provider = getDefaultProvider(chain.rpc);
    const walletConnected = wallet.connect(provider);

    const tl = new Contract(chain.tokenLinker, ITokenLinker.abi, walletConnected);
    const tokenAddress = tl.getTokenAddress(tokenId);
    if(tokenAddress == AddressZero) throw new Error('Token Must be registered before sending.');
    const token = new Contract(tokenAddress, IERC20,abi, walletConnected);

    await (await tl.sendToken(tokenId, destinationChain, destinationAddress, amount)).wait();
    const tokenId = await tl.getOriginTokenId(tokenAddress);
    return tokenId;
}

async function callContractWithInterchainToken(chain, wallet, tokenId, destinationChain, destinationAddress, amount, data) {
    const provider = getDefaultProvider(chain.rpc);
    const walletConnected = wallet.connect(provider);

    const tl = new Contract(chain.tokenLinker, ITokenLinker.abi, walletConnected);
    const tokenAddress = tl.getTokenAddress(tokenId);
    if(tokenAddress == AddressZero) throw new Error('Token Must be registered before sending.');
    const token = new Contract(tokenAddress, IERC20,abi, walletConnected);

    await (await tl.callContractWithInterchainToken(tokenId, destinationChain, destinationAddress, amount.data)).wait();
    const tokenId = await tl.getOriginTokenId(tokenAddress);
    return tokenId;
}

module.exports = {
    sendToken,
    callContractWithInterchainToken,
}