require('dotenv').config();
const { upgradeUpgradable } = require('@axelar-network/axelar-gmp-sdk-solidity');
const { setJSON, deployContract } = require('@axelar-network/axelar-local-dev');
const { Wallet, getDefaultProvider, Contract } = require('ethers');
const { keccak256 } = require('ethers/lib/utils');
const TokenLinker = require('../artifacts/contracts/InterchainTokenLinker.sol/InterchainTokenLinker.json');
const TokenDeployer = require('../artifacts/contracts/TokenDeployer.sol/TokenDeployer.json');
const chains = require(`../info/${process.env.ENV}.json`);
const testnets = require('../info/testnet.json');

async function upgrade(chain, wallet) {
    const testnet = testnets.find((t) => t.name === chain.name);
    const tl = new Contract(chain.tokenLinker, TokenLinker.abi, wallet);
    const code = await wallet.provider.getCode(await tl.tokenDeployer());
    // change the below to the upgraded code to avoid duplicate upgrades in case of a fail the first time.
    if (keccak256(code) === '0x135a5232bed4d1617deb19bc552668a78c8c9146e26b4de5c0c5806a5e297e0e') return;
    const tokenDeployer = await deployContract(wallet, TokenDeployer);
    chain.tokenDeployer = tokenDeployer.address;
    await upgradeUpgradable(
        testnet.tokenLinker,
        wallet,
        TokenLinker,
        [chain.gateway, chain.gasService, testnet.linkerRouter, tokenDeployer.address, chain.name],
        '0x',
    );

    console.log(keccak256(await wallet.provider.getCode(await tl.tokenDeployer())));
}

if (require.main === module) {
    (async () => {
        const deployerKey = process.env.EVM_PRIVATE_KEY;
        
        for (const chain of chains) {
            const provider = getDefaultProvider(chain.rpc);
            const wallet = new Wallet(deployerKey, provider);
            console.log(`----- ${chain.name}: ------`);
            console.log(`before : ${Number((await provider.getBalance(wallet.address)) / 1e18)}`);
            await upgrade(chain, wallet);
            setJSON(chains, `./info/${process.env.ENV}.json`);
            console.log(`after : ${Number((await provider.getBalance(wallet.address)) / 1e18)}`);
        }
    })();
}
