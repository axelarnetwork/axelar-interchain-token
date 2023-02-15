'use strict';

const TokenLinker = require('../artifacts/contracts/InterchainTokenLinker.sol/InterchainTokenLinker.json');
const TokenDeployer = require('../artifacts/contracts/TokenDeployer.sol/TokenDeployer.json');
const TokenLinkerProxy = require('../artifacts/contracts/proxies/InterchainTokenLinkerProxy.sol/InterchainTokenLinkerProxy.json');
const LinkerRouterProxy = require('../artifacts/contracts/proxies/LinkerRouterProxy.sol/LinkerRouterProxy.json');
const LinkerRouter = require('../artifacts/contracts/LinkerRouter.sol/LinkerRouter.json');
const { deployContract } = require('@axelar-network/axelar-gmp-sdk-solidity/scripts/utils');
const { predictContractConstant, deployUpgradable } = require('@axelar-network/axelar-gmp-sdk-solidity');
const { getDefaultProvider } = require('ethers');

async function deployTokenLinker(chain, wallet) {
    const provider = getDefaultProvider(chain.rpc);
    const walletConnected = wallet.connect(provider);
    const ravAddress = await predictContractConstant(chain.constAddressDeployer, walletConnected, LinkerRouterProxy, 'linkerRouter', []);

    const tokenDeployer = await deployContract(walletConnected, TokenDeployer);
    const tl = await deployUpgradable(
        chain.constAddressDeployer,
        walletConnected,
        TokenLinker,
        TokenLinkerProxy,
        [chain.gateway, chain.gasService, ravAddress, tokenDeployer.address, chain.name],
        [],
        [],
        'tokenLinker',
    );
    const linkerRouter = await deployUpgradable(
        chain.constAddressDeployer,
        walletConnected,
        LinkerRouter,
        LinkerRouterProxy,
        [tl.address, [], []], 
        [],
        [],
        'linkerRouter',
    );

    chain.tokenLinker = tl.address;
    chain.linkerRouter = linkerRouter.address;
}

module.exports = {
    deployTokenLinker,
}