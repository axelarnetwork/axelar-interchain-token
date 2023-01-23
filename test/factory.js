'use strict';

const chai = require('chai');
const { getDefaultProvider, Contract, Wallet, ContractFactory, constants: {AddressZero} } = require('ethers');
const { expect } = chai;
const { keccak256, defaultAbiCoder, RLP, getContractAddress } = require('ethers/lib/utils');
const { setJSON } = require('@axelar-network/axelar-local-dev/dist/utils');
require('dotenv').config();

const ERC20MintableBurnable = require('../artifacts/@axelar-network/axelar-gmp-sdk-solidity/contracts/test/ERC20MintableBurnable.sol/ERC20MintableBurnable.json');
const ITokenLinker = require('../artifacts/contracts/interfaces/ITokenLinker.sol/ITokenLinker.json');
const IERC20 = require('../artifacts/contracts/interfaces/IERC20.sol/IERC20.json');
const TokenLinker = require('../artifacts/contracts/TokenLinker.sol/TokenLinker.json');
const TokenLinkerExecutableTest = require('../artifacts/contracts/test/TokenLinkerExecutableTest.sol/TokenLinkerExecutableTest.json');
const TokenLinkerProxy = require('../artifacts/contracts/proxies/TokenLinkerProxy.sol/TokenLinkerProxy.json');
const RemoteAddressValidatorProxy = require('../artifacts/contracts/proxies/RemoteAddressValidatorProxy.sol/RemoteAddressValidatorProxy.json');
const RemoteAddressValidator = require('../artifacts/contracts/RemoteAddressValidator.sol/RemoteAddressValidator.json');
const IAxelarGasService = require('@axelar-network/axelar-gmp-sdk-solidity/artifacts/contracts/interfaces/IAxelarGasService.sol/IAxelarGasService.json');
const { deployContract } = require('@axelar-network/axelar-gmp-sdk-solidity/scripts/utils');
const { predictContractConstant, deployUpgradable, deployAndInitContractConstant } = require('@axelar-network/axelar-gmp-sdk-solidity');
const { createAndExport, networks } = require('@axelar-network/axelar-local-dev');

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
    const contract = await deployContract(wallet, ERC20MintableBurnable, [name, symbol, decimals]);

    return contract;
}

async function deployTokenLinker(chain) {
    const provider = getDefaultProvider(chain.rpc);
    const walletConnected = wallet.connect(provider);
    const ravAddress = await predictContractConstant(chain.constAddressDeployer, walletConnected, RemoteAddressValidatorProxy, 'remoteAddressValidator', []);
    
    const tl = await deployUpgradable(
        chain.constAddressDeployer,
        walletConnected,
        TokenLinker,
        TokenLinkerProxy,
        [chain.gateway, chain.gasReceiver, ravAddress, chain.name],
        [],
        [],
        'tokenLinker',
    );
    const remoteAddressValidator = await deployUpgradable(
        chain.constAddressDeployer,
        walletConnected,
        RemoteAddressValidator,
        RemoteAddressValidatorProxy,
        [tl.address, [], []], 
        [],
        [],
        'remoteAddressValidator',
    );

    chain.tokenLinker = tl.address;
    chain.remoteAddressValidator = remoteAddressValidator.address;
}

describe('Token Linker Factory', () => {
    before(async () => {
        const deployer_key = keccak256(
            defaultAbiCoder.encode(
                ['string'],
                [process.env.PRIVATE_KEY_GENERATOR],
            ),
        );
        wallet = new Wallet(deployer_key)
        const deployerAddress = new Wallet(deployer_key).address;
        const toFund = [deployerAddress];
        await setupLocal(toFund);
        chains = require('../info/local.json');
        chains[0].gatewayToken = (await deployToken(chains[0], wallet, 'gateway token', 'GT', 6)).address;
        for(const chain of chains) {
            chain.token = (await deployToken(chain, wallet)).address;
            await deployTokenLinker(chain);
            const network = networks.find(network => network.name == chain.name);
            if(chain == chains[0]) {
                await network.deployToken('gateway token', 'GT', 6, BigInt(1e18), chain.gatewayToken);
            } else if (chain == chains[1]) {
                chain.gatewayToken = (await network.deployToken('gateway token', 'GT', 6, BigInt(1e18))).address;
            }

        }
        setJSON(chains, './info/local.json');
        for(const chain of chains) {
            const provider = getDefaultProvider(chain.rpc);
            chain.walletConnected = wallet.connect(provider);
            chain.tl = new Contract(chain.tokenLinker, ITokenLinker.abi, chain.walletConnected);
            chain.rav = new Contract(chain.remoteAddressValidator, RemoteAddressValidator.abi, chain.walletConnected);
            chain.tok = new Contract(chain.token, ERC20MintableBurnable.abi, chain.walletConnected);
            if(chain.gatewayToken) chain.gatewayTok = new Contract(chain.gatewayToken, ERC20MintableBurnable.abi, chain.walletConnected);
        }
    });

    it(`Should Register a Token`, async () => {
        const origin = chains[0];
        
        await (await origin.tl.registerToken(origin.token)).wait();
        const tokenId = await origin.tl.getNativeTokenId(origin.token);
        const address = await origin.tl.getTokenAddress(tokenId);
        expect(address).to.equal(origin.token);
    });
    it(`Should deploy a remote token`, async() => {
        const origin = chains[0];
        const destination = chains[1];

        const tokenId = await origin.tl.getNativeTokenId(origin.token);
        const receipt = await (await origin.tl.deployRemoteTokens(tokenId, [destination.name], {value: 1e7})).wait();
        await new Promise((resolve) => {
            setTimeout(() => {
                resolve();
            }, 500);
        });
        expect(await destination.tl.getTokenAddress(tokenId)).to.not.equal(AddressZero);
    });
    it(`Should send some token from origin to destination`, async() => {
        const origin = chains[0];
        const destination = chains[1];
        const amount = 1e6;

        await (await origin.tok.mint(wallet.address, amount)).wait();
        await (await origin.tok.approve(origin.tl.address, amount)).wait();

        const tokenId = await origin.tl.getNativeTokenId(origin.token);
        await (await origin.tl.sendToken(tokenId, destination.name, wallet.address, amount, {value: 1e6})).wait();
        await new Promise((resolve) => {
            setTimeout(() => {
                resolve();
            }, 500);
        });
        const tokenAddr = await destination.tl.getTokenAddress(tokenId)
        const token = new Contract(tokenAddr, IERC20.abi, destination.walletConnected);
        expect(Number(await token.balanceOf(wallet.address))).to.equal(amount);
    });
    it(`Should send some token back`, async() => {
        const origin = chains[0];
        const destination = chains[1];
        const amount = 1e6;

        const tokenId = await origin.tl.getNativeTokenId(origin.token);
        const tokenAddr = await destination.tl.getTokenAddress(tokenId)
        const token = new Contract(tokenAddr, IERC20.abi, destination.walletConnected);
        await (await token.approve(destination.tl.address, amount)).wait();

        await (await destination.tl.sendToken(tokenId, origin.name, wallet.address, amount, {value: 1e6})).wait();

        await new Promise((resolve) => {
            setTimeout(() => {
                resolve();
            }, 500);
        });

        expect(Number(await origin.tok.balanceOf(wallet.address))).to.equal(amount);
    });

    it(`Should register a token and deploy a remote token in one go`, async() => {
        const origin = chains[1];
        const destination = chains[2];

        const receipt = await (await origin.tl.registerTokenAndDeployRemoteTokens(origin.token, [destination.name], {value: 1e7})).wait();
        await new Promise((resolve) => {
            setTimeout(() => {
                resolve();
            }, 500);
        });
        const tokenId = await origin.tl.getNativeTokenId(origin.token);
        expect(await destination.tl.getTokenAddress(tokenId)).to.not.equal(AddressZero);
    });
    it(`Should send some token from origin to destination`, async() => {
        const origin = chains[1];
        const destination = chains[2];
        const amount = 1e6;

        await (await origin.tok.mint(wallet.address, amount)).wait();
        await (await origin.tok.approve(origin.tl.address, amount)).wait();

        const tokenId = await origin.tl.getNativeTokenId(origin.token);
        await (await origin.tl.sendToken(tokenId, destination.name, wallet.address, amount, {value: 1e6})).wait();
        await new Promise((resolve) => {
            setTimeout(() => {
                resolve();
            }, 500);
        });
        const tokenAddr = await destination.tl.getTokenAddress(tokenId)
        const token = new Contract(tokenAddr, IERC20.abi, destination.walletConnected);
        expect(Number(await token.balanceOf(wallet.address))).to.equal(amount);
    });
    it(`Should send some token back`, async() => {
        const origin = chains[1];
        const destination = chains[2];
        const amount = 1e6;

        const tokenId = await origin.tl.getNativeTokenId(origin.token);
        const tokenAddr = await destination.tl.getTokenAddress(tokenId)
        const token = new Contract(tokenAddr, IERC20.abi, destination.walletConnected);
        await (await token.approve(destination.tl.address, amount)).wait();

        await (await destination.tl.sendToken(tokenId, origin.name, wallet.address, amount, {value: 1e6})).wait();

        await new Promise((resolve) => {
            setTimeout(() => {
                resolve();
            }, 500);
        });
        
        expect(Number(await origin.tok.balanceOf(wallet.address))).to.equal(amount);
    });

    it(`Should Register a gateway Token`, async () => {
        const origin = chains[0];
        const destination = chains[1];
        await (await origin.tl.registerNativeGatewayToken(origin.gatewayToken)).wait();
        const tokenId = await origin.tl.getNativeTokenId(origin.gatewayToken);

        expect(await origin.tl.getTokenAddress(tokenId)).to.equal(origin.gatewayToken);

        await (await destination.tl.registerRemoteGatewayToken(destination.gatewayToken, tokenId, origin.name)).wait();
    
        expect(await destination.tl.getTokenAddress(tokenId)).to.equal(destination.gatewayToken);
    });

    it(`Should send some gateway token from origin to destination`, async () => {
        const origin = chains[0];
        const destination = chains[1];
        const amount = 1e6;

        await (await origin.gatewayTok.mint(wallet.address, amount)).wait();
        await (await origin.gatewayTok.approve(origin.tl.address, amount)).wait();

        const tokenId = await origin.tl.getNativeTokenId(origin.gatewayToken);
        await (await origin.tl.sendToken(tokenId, destination.name, wallet.address, amount, {value: 1e6})).wait();

        await new Promise((resolve) => {
            setTimeout(() => {
                resolve();
            }, 500);
        });
        const tokenAddr = await destination.tl.getTokenAddress(tokenId)
        const token = new Contract(tokenAddr, IERC20.abi, destination.walletConnected);
        expect(Number(await token.balanceOf(wallet.address))).to.equal(amount);
    });

    it(`Should send some gateway token back`, async() => {
        const origin = chains[0];
        const destination = chains[1];
        const finalDestination = chains[2];
        const amount = 1e6;

        const tokenId = await origin.tl.getNativeTokenId(origin.gatewayToken);
        const tokenAddr = await destination.tl.getTokenAddress(tokenId)
        const token = new Contract(tokenAddr, IERC20.abi, destination.walletConnected);
        await (await token.approve(destination.tl.address, amount)).wait();
        const payload = defaultAbiCoder.encode(['uint256', 'string', 'bytes'], [3, finalDestination.name, wallet.address]);
        const payload2 = defaultAbiCoder.encode(['uint256', 'bytes32', 'bytes', 'uint256'],[0, tokenId, wallet.address, amount]);
        const gasReceiver = new Contract(origin.gasReceiver, IAxelarGasService.abi, origin.walletConnected);

        await (await origin.tl.deployRemoteTokens(tokenId, [finalDestination.name], {value: 1e7})).wait()
        await (await gasReceiver.payNativeGasForContractCall(
            origin.tl.address,
            finalDestination.name,
            finalDestination.tl.address,
            payload2,
            wallet.address,
            {value: 1e6},
        )).wait();
        await (await destination.tl.sendTokenWithData(tokenId, origin.name, origin.tl.address, amount, payload, {value: 1e6})).wait();

        await new Promise((resolve) => {
            setTimeout(() => {
                resolve();
            }, 1000);
        });

        const finalToken = new Contract(await finalDestination.tl.getTokenAddress(tokenId), IERC20.abi, finalDestination.walletConnected);
        expect(Number(await finalToken.balanceOf(wallet.address))).to.equal(amount);
    });

})