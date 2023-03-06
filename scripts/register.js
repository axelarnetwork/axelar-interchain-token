const { Contract, getDefaultProvider } = require("ethers");
const { keccak256, defaultAbiCoder } = require("ethers/lib/utils");
const ITokenLinker = require('../artifacts/contracts/interfaces/IInterchainTokenLinker.sol/IInterchainTokenLinker.json');

async function registerOriginToken(chain, wallet, tokenAddress) {
    const provider = getDefaultProvider(chain.rpc);
    const walletConnected = wallet.connect(provider);

    const tl = new Contract(chain.tokenLinker, ITokenLinker.abi, walletConnected);
    await (await tl.registerOriginToken(tokenAddress)).wait();

    const tokenId = await tl.getOriginTokenId(tokenAddress);
    return tokenId;
}

async function deployRemoteTokens(chain, wallet, tokenId, destinationChains, gasAmounts) {
    const provider = getDefaultProvider(chain.rpc);
    const walletConnected = wallet.connect(provider);

    const tl = new Contract(chain.tokenLinker, ITokenLinker.abi, walletConnected);

    const totalGas = gasAmounts.reduce((partialSum, a) => partialSum + a, 0);
    await (await tl.deployRemoteTokens(tokenId, destinationChains, gasAmounts, {value: totalGas})).wait();
}

async function registerOriginTokenAndDeployRemoteTokens(chain, wallet, tokenAddress, destinationChains, gasAmounts) {
    const provider = getDefaultProvider(chain.rpc);
    const walletConnected = wallet.connect(provider);

    const tl = new Contract(chain.tokenLinker, ITokenLinker.abi, walletConnected);

    const totalGas = gasAmounts.reduce((partialSum, a) => partialSum + a, 0);
    await (await tl.deployRemoteTokens(tokenId, destinationChains, gasAmounts, {value: totalGas})).wait();

    const tokenId = await tl.getOriginTokenId(tokenAddress);
    return tokenId;
}

module.exports = {
    registerOriginToken,
    deployRemoteTokens,
    registerOriginTokenAndDeployRemoteTokens,
}