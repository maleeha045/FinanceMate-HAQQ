import { BigNumber, Contract, Signer } from 'ethers';
import { ethers,upgrades } from 'hardhat';
import OnchainID from '@onchain-id/solidity';
import "@openzeppelin/hardhat-upgrades";
require("dotenv").config();


export async function deployIdentityProxy(implementationAuthority: Contract['address'], managementKey: string, signer: Signer) {
    const identity = await new ethers.ContractFactory(OnchainID.contracts.IdentityProxy.abi, OnchainID.contracts.IdentityProxy.bytecode, signer).deploy(
      implementationAuthority,
      managementKey,
    );
  
    return ethers.getContractAt('Identity', identity.address, signer);
  }

const main =  async function deployFullSuiteFixture() {

    
     const deployerPrivateKey = `${process.env.deployerPrivateKey}`; //4
     const tokenIssuerPrivateKey = `${process.env.tokenIssuerPrivateKey}`;//4
     const tokenAgentPrivateKey = `${process.env.tokenAgentPrivateKey}`;//1
     const tokenAdminPrivateKey = `${process.env.tokenAdminPrivateKey}`;//1
     const claimIssuerPrivateKey = `${process.env.claimIssuerPrivateKey}`;//3

     //mainnet
    // const provider = new ethers.providers.JsonRpcProvider("https://rpc.eth.haqq.network");
    //testnet
    const provider = new ethers.providers.JsonRpcProvider("https://te2-s1-evm-rpc.haqq.sh");



    const deployer = new ethers.Wallet(deployerPrivateKey, provider);
    const tokenIssuer = new ethers.Wallet(tokenIssuerPrivateKey, provider);
    const tokenAgent = new ethers.Wallet(tokenAgentPrivateKey, provider);
    const tokenAdmin = new ethers.Wallet(tokenAdminPrivateKey, provider);
    const claimIssuer = new ethers.Wallet(claimIssuerPrivateKey, provider);

  // Deploy implementations
  const claimTopicsRegistryImplementation = await ethers.deployContract('ClaimTopicsRegistry', deployer);
  const trustedIssuersRegistryImplementation = await ethers.deployContract('TrustedIssuersRegistry', deployer);
  const identityRegistryStorageImplementation = await ethers.deployContract('IdentityRegistryStorage', deployer);
  const identityRegistryImplementation = await ethers.deployContract('IdentityRegistry', deployer);
  const modularComplianceImplementation = await ethers.deployContract('ModularCompliance', deployer);
  const tokenImplementation = await ethers.deployContract('Token', deployer);
  const identityImplementation = await new ethers.ContractFactory(
    OnchainID.contracts.Identity.abi,
    OnchainID.contracts.Identity.bytecode,
    deployer,
  ).deploy(deployer.address, true);

  const identityImplementationAuthority = await new ethers.ContractFactory(
    OnchainID.contracts.ImplementationAuthority.abi,
    OnchainID.contracts.ImplementationAuthority.bytecode,
    deployer,
  ).deploy(identityImplementation.address);

  const identityFactory = await new ethers.ContractFactory(OnchainID.contracts.Factory.abi, OnchainID.contracts.Factory.bytecode, deployer).deploy(
    identityImplementationAuthority.address,
  );

  const trexImplementationAuthority = await ethers.deployContract(
    'TREXImplementationAuthority',
    [true, ethers.constants.AddressZero, ethers.constants.AddressZero],
    deployer,
  );
  const versionStruct = {
    major: 4,
    minor: 0,
    patch: 0,
  };
  const contractsStruct = {
    tokenImplementation: tokenImplementation.address,
    ctrImplementation: claimTopicsRegistryImplementation.address,
    irImplementation: identityRegistryImplementation.address,
    irsImplementation: identityRegistryStorageImplementation.address,
    tirImplementation: trustedIssuersRegistryImplementation.address,
    mcImplementation: modularComplianceImplementation.address,
  };

  await trexImplementationAuthority.connect(deployer).addAndUseTREXVersion(versionStruct, contractsStruct);

  const trexFactory = await ethers.deployContract('TREXFactory', [trexImplementationAuthority.address, identityFactory.address], deployer);
  await identityFactory.connect(deployer).addTokenFactory(trexFactory.address);

  const claimTopicsRegistry = await ethers
    .deployContract('ClaimTopicsRegistryProxy', [trexImplementationAuthority.address], deployer)
    .then(async (proxy) => ethers.getContractAt('ClaimTopicsRegistry', proxy.address));

  const trustedIssuersRegistry = await ethers
    .deployContract('TrustedIssuersRegistryProxy', [trexImplementationAuthority.address], deployer)
    .then(async (proxy) => ethers.getContractAt('TrustedIssuersRegistry', proxy.address));

  const identityRegistryStorage = await ethers
    .deployContract('IdentityRegistryStorageProxy', [trexImplementationAuthority.address], deployer)
    .then(async (proxy) => ethers.getContractAt('IdentityRegistryStorage', proxy.address));

  const defaultCompliance = await ethers.deployContract('DefaultCompliance', deployer);

  const identityRegistry = await ethers
    .deployContract(
      'IdentityRegistryProxy',
      [trexImplementationAuthority.address, trustedIssuersRegistry.address, claimTopicsRegistry.address, identityRegistryStorage.address],
      deployer,
    )
    .then(async (proxy) => ethers.getContractAt('IdentityRegistry', proxy.address));

  const tokenOID = await deployIdentityProxy(identityImplementationAuthority.address, tokenIssuer.address, deployer);
  const tokenName = 'TREXDINO';
  const tokenSymbol = 'TREX';
  const tokenDecimals = BigNumber.from('0');
  const token = await ethers
    .deployContract(
      'TokenProxy',
      [
        trexImplementationAuthority.address,
        identityRegistry.address,
        defaultCompliance.address,
        tokenName,
        tokenSymbol,
        tokenDecimals,
        tokenOID.address,
      ],
      deployer,
    )
    .then(async (proxy) => ethers.getContractAt('Token', proxy.address));

  const agentManager = await ethers.deployContract('AgentManager', [token.address], tokenAgent);

  await identityRegistryStorage.connect(deployer).bindIdentityRegistry(identityRegistry.address);

  await token.connect(deployer).addAgent(tokenAgent.address);

  const claimTopics = [ethers.utils.id('CLAIM_TOPIC')];
  await claimTopicsRegistry.connect(deployer).addClaimTopic(claimTopics[0]);

  const claimIssuerContract = await ethers.deployContract('ClaimIssuer', [claimIssuer.address], claimIssuer);
  await claimIssuerContract
    .connect(claimIssuer)
    .addKey(ethers.utils.keccak256(ethers.utils.defaultAbiCoder.encode(['address'], [claimIssuer.address])), 3, 1);

  await trustedIssuersRegistry.connect(deployer).addTrustedIssuer(claimIssuerContract.address, claimTopics);

  await identityRegistry.connect(deployer).addAgent(tokenAgent.address);
  await identityRegistry.connect(deployer).addAgent(token.address);

  await agentManager.connect(tokenAgent).addAgentAdmin(tokenAdmin.address);
  await token.connect(deployer).addAgent(agentManager.address);
  await identityRegistry.connect(deployer).addAgent(agentManager.address);

  await token.connect(tokenAgent).unpause();

    const poolAddress = "0xE58Ef5a5D1735CF8B36cb63f618dfbdF58b14CCA";  
    const USDC = "0x80b5a32E4F032B2a058b4F29EC95EEfEEB87aDcd";

    const invoiceNFTContract = await ethers.deployContract("InvoiceNFT",deployer);
  
    const haqqContract = await ethers.getContractFactory("HaqqInvoiceMateContract");
    const HaqqContract = await upgrades.deployProxy(haqqContract, [poolAddress,USDC,invoiceNFTContract.address,deployer.address]);

    console.log("Contract proxy deployed to:", HaqqContract.address);

    console.log(identityImplementationAuthority.address);
    console.log(token.address);
    console.log(identityRegistry.address);
    console.log(claimIssuerContract.address);
    console.log(trexImplementationAuthority.address);
    console.log(defaultCompliance.address);
    console.log(tokenOID.address);
    console.log(invoiceNFTContract.address);
  
  

  return {
    accounts: {
      deployer,
      tokenIssuer,
      tokenAgent,
      tokenAdmin,
      claimIssuer,
  
    },
    suite: {
      claimIssuerContract,
      claimTopicsRegistry,
      trustedIssuersRegistry,
      identityRegistryStorage,
      defaultCompliance,
      identityRegistry,
      tokenOID,
      token,
      agentManager,
    },
    authorities: {
      trexImplementationAuthority,
      identityImplementationAuthority,
    },
    factories: {
      trexFactory,
      identityFactory,
    },
    implementations: {
      identityImplementation,
      claimTopicsRegistryImplementation,
      trustedIssuersRegistryImplementation,
      identityRegistryStorageImplementation,
      identityRegistryImplementation,
      modularComplianceImplementation,
      tokenImplementation,
    },
  };
}
main();