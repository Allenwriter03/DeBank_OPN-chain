require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

const PRIVATE_KEY = process.env.PRIVATE_KEY || "";
const OPN_TESTNET_RPC_URL = process.env.OPN_TESTNET_RPC_URL || "https://testnet-rpc.iopn.tech";

/** @type {import('hardhat/config').HardhatUserConfig} */
module.exports = {
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: { enabled: true, runs: 200 },
    },
  },
  networks: {
    opnTestnet: {
      url: OPN_TESTNET_RPC_URL,
      chainId: 984,
      accounts: PRIVATE_KEY ? [PRIVATE_KEY] : [],
    },
  },
};
