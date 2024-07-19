import '@xyrusworx/hardhat-solidity-json';
import '@nomicfoundation/hardhat-toolbox';
import { HardhatUserConfig } from 'hardhat/config';
import '@openzeppelin/hardhat-upgrades';
import 'solidity-coverage';
import '@nomiclabs/hardhat-solhint';
import '@primitivefi/hardhat-dodoc';
require("dotenv").config();

const config: HardhatUserConfig = {
  solidity: {
    version: '0.8.17',
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks:{
     haqqTestnet:{
      url:"https://te2-s1-evm-rpc.haqq.sh",
      chainId: 54211,
      accounts:[`${process.env.deployerPrivateKey}`]
    },
    haqqMainnet:{
      url:"https://rpc.eth.haqq.network",
      chainId: 11235,
      accounts:[`${process.env.deployerPrivateKey}`]
    },
  },
  etherscan: {
    apiKey: `${process.env.apiKey}`,
    customChains: [
      {
        network: "haqqTestnet",
        chainId: 54211,
        urls: {
          apiURL: "https://explorer.testedge2.haqq.network/api",
          browserURL: "https://explorer.testedge2.haqq.network",
        },
      },
   
      // {
      //     network: "haqqMainnet",
      //     chainId: 11235,
      //     urls: {
      //       apiURL: "https://explorer.haqq.network/api",
      //       browserURL: "https://explorer.haqq.network/",
      //     },
      //   },
    ],
  },
  gasReporter: {
    enabled: true,
  },
  dodoc: {
    runOnCompile: false,
    debugMode: true,
    outputDir: "./docgen",
    freshOutput: true,
  },
};

export default config;
