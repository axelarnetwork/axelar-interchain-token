'use strict';

const chai = require('chai');
const {
    getDefaultProvider,
    Contract,
    Wallet,
    constants: { AddressZero },
} = require('ethers');
const { expect } = chai;
const { keccak256, defaultAbiCoder } = require('ethers/lib/utils');
const { setJSON } = require('@axelar-network/axelar-local-dev/dist/utils');
require('dotenv').config();

const ERC20MintableBurnable = require('../artifacts/contracts/ERC20BurnableMintable.sol/ERC20BurnableMintable.json');
const IERC20MintableBurnable = require('../artifacts/contracts/interfaces/IERC20BurnableMintable.sol/IERC20BurnableMintable.json');
const ITokenLinker = require('../artifacts/contracts/interfaces/IInterchainTokenLinker.sol/IInterchainTokenLinker.json');
const IERC20 = require('../artifacts/contracts/interfaces/IERC20Named.sol/IERC20Named.json');
const LinkerRouter = require('../artifacts/contracts/LinkerRouter.sol/LinkerRouter.json');
const IAxelarGasService = require('@axelar-network/axelar-gmp-sdk-solidity/artifacts/contracts/interfaces/IAxelarGasService.sol/IAxelarGasService.json');
const TokenProxy = require('../artifacts/contracts/proxies/TokenProxy.sol/TokenProxy.json');
const { deployContract } = require('@axelar-network/axelar-gmp-sdk-solidity/scripts/utils');
const { createAndExport, networks } = require('@axelar-network/axelar-local-dev');
const { deployRemoteTokens, registerOriginToken } = require('../scripts/register');

let chains;
let wallet;

async function setupLocal(toFund) {
    await createAndExport({
        chainOutputPath: './info/local.json',
        accountsToFund: toFund,
        relayInterval: 100,
    });
}

async function deployToken(chain, walletUnconnected, name = 'Subnet Token', symbol = 'ST', decimals = 18) {
    const provider = getDefaultProvider(chain.rpc);
    const wallet = walletUnconnected.connect(provider);
    console.log(`Deploying a token {name: ${name}, symbol: ${symbol}, decimals: ${decimals}}`);
    const proxy = await deployContract(wallet, TokenProxy, [chain.tokenImplementation, name, symbol, decimals, wallet.address]);
    console.log(`Deployed at: ${proxy.address}`);
    const contract = new Contract(proxy.address, IERC20MintableBurnable.abi, wallet);

    return contract;
}

before(async() => {
    const deployerKey = keccak256(defaultAbiCoder.encode(['string'], [process.env.PRIVATE_KEY_GENERATOR]));
    wallet = new Wallet(deployerKey);
    const deployerAddress = new Wallet(deployerKey).address;
    const toFund = [deployerAddress];
    await setupLocal(toFund);
    chains = require('../info/local.json');

    const { deployTokenLinker } = require('../scripts/deploy.js');

    for (const chain of chains) {
        await deployTokenLinker(chain, wallet);
        chain.token = (await deployToken(chain, wallet)).address;
        const network = networks.find((network) => network.name === chain.name);

        if (chain === chains[0]) {
            chain.gatewayToken = (await deployToken(chains[0], wallet, 'gateway token', 'GT', 6)).address;
            await network.deployToken('gateway token', 'GT', 6, BigInt(1e18), chain.gatewayToken);
        } else if (chain === chains[1]) {
            chain.gatewayToken = (await network.deployToken('gateway token', 'GT', 6, BigInt(1e18))).address;
        }
    }

    setJSON(chains, './info/local.json');

});

describe('Token', () => {
    let token;
    const name = 'Test Token';
    const symbol = 'TT';
    const decimals = 13;
    before(async() => {
        token = await deployToken(chains[0], wallet, name, symbol, decimals);
    });
    it('Should Test that the token has the correct name, symbol, decimals and owner', async() => {
        console.log(await token.name());
        expect(await token.name()).to.equal(name);
        expect(await token.symbol()).to.equal(symbol);
        expect(await token.decimals()).to.equal(decimals);
        expect(await token.owner()).to.equal(wallet.address);
    });
});

describe('Token Linker', () => {
    before(async () => {
        for (const chain of chains) {
            const provider = getDefaultProvider(chain.rpc);
            chain.walletConnected = wallet.connect(provider);
            chain.tl = new Contract(chain.tokenLinker, ITokenLinker.abi, chain.walletConnected);
            chain.rav = new Contract(chain.linkerRouter, LinkerRouter.abi, chain.walletConnected);
            chain.tok = new Contract(chain.token, ERC20MintableBurnable.abi, chain.walletConnected);
            if (chain.gatewayToken) chain.gatewayTok = new Contract(chain.gatewayToken, ERC20MintableBurnable.abi, chain.walletConnected);
        }
    });

    it(`Should Register a Token`, async () => {
        const origin = chains[0];

        const tokenId = await registerOriginToken(origin, wallet, origin.token);
        const address = await origin.tl.getTokenAddress(tokenId);
        expect(address).to.equal(origin.token);
    });
    it(`Should deploy a remote token`, async () => {
        const origin = chains[0];
        const destination = chains[1];

        const tokenId = await origin.tl.getOriginTokenId(origin.token);
        await deployRemoteTokens(origin, wallet, tokenId, [destination.name], [1e7]);

        await new Promise((resolve) => {
            setTimeout(() => {
                resolve();
            }, 500);
        });
        expect(await destination.tl.getTokenAddress(tokenId)).to.not.equal(AddressZero);
    });
    it(`Should fail to deploy a remote token before registering a token`, async () => {
        const origin = chains[0];
        const destination = chains[1];

        const newToken = await deployToken(origin, wallet, 'Unregistered Token', 'UT', 18);

        const tokenId = await origin.tl.getOriginTokenId(origin.token);
        await deployRemoteTokens(origin, wallet, tokenId, [destination.name], [1e7]);

        await new Promise((resolve) => {
            setTimeout(() => {
                resolve();
            }, 500);
        });
        expect(await destination.tl.getTokenAddress(tokenId)).to.not.equal(AddressZero);
    });
    it(`Should send some token from origin to destination`, async () => {
        const origin = chains[0];
        const destination = chains[1];
        const amount = 1e6;

        await (await origin.tok.mint(wallet.address, amount)).wait();
        await (await origin.tok.approve(origin.tl.address, amount)).wait();

        const tokenId = await origin.tl.getOriginTokenId(origin.token);
        await (await origin.tl.sendToken(tokenId, destination.name, wallet.address, amount, { value: 1e6 })).wait();
        await new Promise((resolve) => {
            setTimeout(resolve, 500);
        });
        const tokenAddr = await destination.tl.getTokenAddress(tokenId);
        const token = new Contract(tokenAddr, IERC20.abi, destination.walletConnected);
        expect(Number(await token.balanceOf(wallet.address))).to.equal(amount);
    });
    it(`Should send some token back`, async () => {
        const origin = chains[0];
        const destination = chains[1];
        const amount = 1e6;

        const tokenId = await origin.tl.getOriginTokenId(origin.token);
        const tokenAddr = await destination.tl.getTokenAddress(tokenId);
        const token = new Contract(tokenAddr, IERC20.abi, destination.walletConnected);
        await (await token.approve(destination.tl.address, amount)).wait();

        await (await destination.tl.sendToken(tokenId, origin.name, wallet.address, amount, { value: 1e6 })).wait();

        await new Promise((resolve) => {
            setTimeout(() => {
                resolve();
            }, 500);
        });

        expect(Number(await origin.tok.balanceOf(wallet.address))).to.equal(amount);
    });

    it(`Should register a token and deploy a remote token in one go`, async () => {
        const origin = chains[1];
        const destination = chains[2];

        await (
            await origin.tl.registerOriginTokenAndDeployRemoteTokens(origin.token, [destination.name], [1e7], { value: 1e7 })
        ).wait();
        await new Promise((resolve) => {
            setTimeout(() => {
                resolve();
            }, 500);
        });
        const tokenId = await origin.tl.getOriginTokenId(origin.token);
        expect(await destination.tl.getTokenAddress(tokenId)).to.not.equal(AddressZero);
    });
    it(`Should send some token from origin to destination`, async () => {
        const origin = chains[1];
        const destination = chains[2];
        const amount = 1e6;

        await (await origin.tok.mint(wallet.address, amount)).wait();
        await (await origin.tok.approve(origin.tl.address, amount)).wait();

        const tokenId = await origin.tl.getOriginTokenId(origin.token);
        await (await origin.tl.sendToken(tokenId, destination.name, wallet.address, amount, { value: 1e6 })).wait();
        await new Promise((resolve) => {
            setTimeout(() => {
                resolve();
            }, 500);
        });
        const tokenAddr = await destination.tl.getTokenAddress(tokenId);
        const token = new Contract(tokenAddr, IERC20.abi, destination.walletConnected);
        expect(Number(await token.balanceOf(wallet.address))).to.equal(amount);
    });
    it(`Should send some token back`, async () => {
        const origin = chains[1];
        const destination = chains[2];
        const amount = 1e6;

        const tokenId = await origin.tl.getOriginTokenId(origin.token);
        const tokenAddr = await destination.tl.getTokenAddress(tokenId);
        const token = new Contract(tokenAddr, IERC20.abi, destination.walletConnected);
        await (await token.approve(destination.tl.address, amount)).wait();
        await (await destination.tl.sendToken(tokenId, origin.name, wallet.address, amount, { value: 1e6 })).wait();

        await new Promise((resolve) => {
            setTimeout(() => {
                resolve();
            }, 500);
        });

        expect(Number(await origin.tok.balanceOf(wallet.address))).to.equal(amount);
    });

    it(`Should deploy an interchain token and deploy a remote token in one go`, async () => {
        const origin = chains[1];
        const destination = chains[2];
        await (
            await origin.tl.deployInterchainToken(
                'Interchain Token',
                'IT',
                18,
                origin.walletConnected.address,
                keccak256('0x012345675748594069'),
                [destination.name],
                [1e7],
                { value: 1e7 },
            )
        ).wait();

        const filter = origin.tl.filters.TokenRegistered();
        const logs = await origin.tl.queryFilter(filter);
        const tokenId = logs[logs.length - 1].args.tokenId;
        const tokenAddress = logs[logs.length - 1].args.tokenAddress;

        origin.iTok = new Contract(tokenAddress, ERC20MintableBurnable.abi, origin.walletConnected);

        await new Promise((resolve) => {
            setTimeout(() => {
                resolve();
            }, 500);
        });
        expect(await destination.tl.getTokenAddress(tokenId)).to.not.equal(AddressZero);
    });
    it(`Should send some token from origin to destination`, async () => {
        const origin = chains[1];
        const destination = chains[2];
        const amount = 1e6;

        await (await origin.iTok.mint(wallet.address, amount)).wait();
        await (await origin.iTok.approve(origin.tl.address, amount)).wait();

        const tokenId = await origin.tl.getTokenId(origin.iTok.address);
        await (await origin.tl.sendToken(tokenId, destination.name, wallet.address, amount, { value: 1e6 })).wait();
        await new Promise((resolve) => {
            setTimeout(() => {
                resolve();
            }, 500);
        });
        const tokenAddr = await destination.tl.getTokenAddress(tokenId);
        const token = new Contract(tokenAddr, IERC20.abi, destination.walletConnected);
        expect(Number(await token.balanceOf(wallet.address))).to.equal(amount);
    });
    it(`Should send some token back`, async () => {
        const origin = chains[1];
        const destination = chains[2];
        const amount = 1e6;

        const tokenId = await origin.tl.getTokenId(origin.iTok.address);
        const tokenAddr = await destination.tl.getTokenAddress(tokenId);
        const token = new Contract(tokenAddr, IERC20.abi, destination.walletConnected);
        await (await token.approve(destination.tl.address, amount)).wait();
        await (await destination.tl.sendToken(tokenId, origin.name, wallet.address, amount, { value: 1e6 })).wait();

        await new Promise((resolve) => {
            setTimeout(() => {
                resolve();
            }, 500);
        });

        expect(Number(await origin.iTok.balanceOf(wallet.address))).to.equal(amount);
    });

    it('Should Register some chains as gateway supported.', async () => {
        const origin = chains[0];
        const destination = chains[1];
        await (await origin.rav.addGatewaySupportedChains([destination.name])).wait();
        await (await destination.rav.addGatewaySupportedChains([origin.name])).wait();
    });

    let origin;
    let gatewaySupported;
    let gatewayUnsupported;
    let tokenId;

    it(`Should Register a native gateway Token`, async () => {
        origin = chains[0];
        gatewaySupported = chains[1];
        gatewayUnsupported = chains[2];
        await (await origin.tl.registerOriginGatewayToken('GT')).wait();
        const filter = await origin.tl.filters.TokenRegistered();
        const logs = await origin.tl.queryFilter(filter);
        const log = logs[logs.length - 1];
        tokenId = await origin.tl.getOriginTokenId(origin.gatewayToken);

        expect(await origin.tl.getTokenAddress(tokenId)).to.equal(origin.gatewayToken);
    });
    it(`Should Register a remote gateway Token`, async () => {

        await (await gatewaySupported.tl.registerRemoteGatewayToken('GT', tokenId, origin.name)).wait();

        expect(await gatewaySupported.tl.getTokenAddress(tokenId)).to.equal(gatewaySupported.gatewayToken);
    });
    it(`Should deploy a remote gateway Token to an unsupported chain`, async () => {

        await (await origin.tl.deployRemoteTokens(tokenId, [gatewayUnsupported.name], [1e7], { value: 1e7 })).wait();

        await new Promise((resolve) => {
            setTimeout(() => {
                resolve();
            }, 500);
        });

        expect(await gatewayUnsupported.tl.getTokenAddress(tokenId)).to.not.equal(AddressZero);
    });

    const aliases = ['origin', 'gateway supported', 'gateway unsupported'];

    const amounts = [0, 0, 0];
    amounts[1] = 123456;
    amounts[2] = amounts[1];
    amounts[0] = amounts[1] * 2;
    let tokens;

    it(`Should do some setup before sending`, async () => {
        await await origin.gatewayTok.mint(wallet.address, 2 * amounts[0]);
        tokens = [
            origin.gatewayTok,
            gatewaySupported.gatewayTok,
            new Contract(await gatewayUnsupported.tl.getTokenAddress(tokenId), IERC20.abi, gatewayUnsupported.walletConnected),
        ];
    });

    for (let i = 0; i < 3; i++) {
        for (let j = 0; j < 3; j++) {
            if (i === j) continue;
            it(`Should send ${amounts[i]} token from ${aliases[i]} to ${aliases[j]}`, async () => {
                const source = chains[i];
                const destination = chains[j];
                const token1 = tokens[i];
                const token2 = tokens[j];
                const amount = amounts[i];
                const balance = await token2.balanceOf(wallet.address);

                await (await token1.approve(source.tokenLinker, amount)).wait();

                if (i + j === 3) {
                    const payload = (await origin.tl.populateTransaction.selfGiveToken(tokenId, wallet.address, amount)).data;
                    const gasService = new Contract(origin.gasService, IAxelarGasService.abi, origin.walletConnected);
                    
                    if (i === 1) {
                        await (
                            await gasService.payNativeGasForContractCall(
                                origin.tokenLinker,
                                destination.name,
                                destination.tokenLinker,
                                payload,
                                wallet.address,
                                { value: 1e6 },
                            )
                        ).wait();
                    } else {
                        await (
                            await gasService.payNativeGasForContractCallWithToken(
                                origin.tokenLinker,
                                destination.name,
                                destination.tokenLinker,
                                payload,
                                'GT',
                                amount,
                                wallet.address,
                                { value: 1e6 },
                            )
                        ).wait();
                    }
                }
                
                await (await source.tl.sendToken(tokenId, destination.name, wallet.address, amount, { value: 1e6 })).wait();

                await new Promise((resolve) => {
                    setTimeout(() => {
                        resolve();
                    }, 1000);
                });

                const balanceNew = await token2.balanceOf(wallet.address);
                expect(balanceNew - balance).to.equal(amount);
            });
        }
    }
});
