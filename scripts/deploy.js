'use strict';

require('dotenv').config();

const TokenLinker = require('../artifacts/contracts/InterchainTokenLinker.sol/InterchainTokenLinker.json');
const TokenDeployer = require('../artifacts/contracts/TokenDeployer.sol/TokenDeployer.json');
const TokenLinkerProxy = require('../artifacts/contracts/proxies/InterchainTokenLinkerProxy.sol/InterchainTokenLinkerProxy.json');
const LinkerRouterProxy = require('../artifacts/contracts/proxies/LinkerRouterProxy.sol/LinkerRouterProxy.json');
const LinkerRouter = require('../artifacts/contracts/LinkerRouter.sol/LinkerRouter.json');
const BytecodeServer = require('../artifacts/contracts/BytecodeServer.sol/BytecodeServer.json');
const Token = require('../artifacts/contracts/ERC20BurnableMintable.sol/ERC20BurnableMintable.json');
const TokenProxy = require('../artifacts/contracts/proxies/TokenProxy.sol/TokenProxy.json');
const { deployContract } = require('@axelar-network/axelar-gmp-sdk-solidity/scripts/utils');
const { getCreate3Address, deployCreate3Upgradable } = require('@axelar-network/axelar-gmp-sdk-solidity');
const { getDefaultProvider, Wallet } = require('ethers');
const { setJSON } = require('@axelar-network/axelar-local-dev');
const chains = require(`../info/${process.env.ENV}.json`);


async function _deployTokenDeployer(chain, wallet) {
    if (chain.tokenDeployer) return;


    console.log(`Deploying ERC20BurnableMintable.`);
    const token = await deployContract(wallet, Token, []);
    chain.tokenImplementation = token.address;
    console.log(`Deployed at: ${token.address}`);

    console.log(`Deploying Bytecode Server.`);
    const bytecodeServer = await deployContract(wallet, BytecodeServer, [TokenProxy.bytecode]);
    chain.bytecodeServer = bytecodeServer.address;
    console.log(`Deployed at: ${bytecodeServer.address}`);

    console.log(`Deploying Token Deployer.`);
    const tokenDeployer = await deployContract(wallet, TokenDeployer, [chain.create3Deployer, bytecodeServer.address]);
    chain.tokenDeployer = tokenDeployer.address;
    console.log(`Deployed at: ${tokenDeployer.address}`);

    setJSON(chains, `./info/${process.env.ENV}.json`);
}

async function _deployTokenLinker(chain, wallet) {
    if (chain.tokenLinker) return;

    const ravAddress = await getCreate3Address(chain.create3Deployer, wallet, 'linkerRouter');
    console.log(`Deploying TokenLinker.`);
    const tl = await deployCreate3Upgradable(
        chain.create3Deployer,
        wallet,
        TokenLinker,
        TokenLinkerProxy,
        [chain.gateway, chain.gasService, ravAddress, chain.tokenDeployer, chain.tokenImplementation, chain.name],
        [],
        '0x',
        'tokenLinker',
    );
    chain.tokenLinker = tl.address;
    console.log(`Deployed at: ${tl.address}`);
    setJSON(chains, `./info/${process.env.ENV}.json`);
}

async function _deployLinkerRouter(chain, wallet) {
    if (chain.linkerRouter) return;

    console.log(`Deploying LinkerRouter.`);
    const linkerRouter = await deployCreate3Upgradable(
        chain.create3Deployer,
        wallet,
        LinkerRouter,
        LinkerRouterProxy,
        [chain.tokenLinker, [], []],
        [],
        '0x',
        'linkerRouter',
    );
    chain.linkerRouter = linkerRouter.address;
    console.log(`Deployed at: ${linkerRouter.address}`);
    setJSON(chains, `./info/${process.env.ENV}.json`);
}

async function reapeat(action, n = 10) {
    for (let i = 0; i < n; i++) {
        try {
            await action();
            return true;
        } catch (e) {
            console.log(`Failed attempt ${i + 1}`);
        }
    }

    return false;
}

async function deployTokenLinker(chain, wallet) {
    const provider = getDefaultProvider(chain.rpc);
    const walletConnected = wallet.connect(provider);
    if (!(await reapeat(async () => await _deployTokenDeployer(chain, walletConnected)))) return;
    if (!(await reapeat(async () => await _deployTokenLinker(chain, walletConnected)))) return;
    await reapeat(async () => await _deployLinkerRouter(chain, walletConnected));
}

module.exports = {
    deployTokenLinker,
};

if (require.main === module) {
    (async () => {
        const deployerKey = process.env.EVM_PRIVATE_KEY;

        for (const chain of chains) {
            const provider = getDefaultProvider(chain.rpc);
            const wallet = new Wallet(deployerKey, provider);
            console.log(`----- ${chain.name}: ------`);
            console.log(`before : ${Number((await provider.getBalance(wallet.address)) / 1e18)}`);
            console.log(wallet.address);
            await deployTokenLinker(chain, wallet);
            setJSON(chains, `./info/${process.env.ENV}.json`);
            console.log(`after : ${Number((await provider.getBalance(wallet.address)) / 1e18)}`);
        }
    })();
}
