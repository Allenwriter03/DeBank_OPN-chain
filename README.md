# DeBank_OPN-chain
A Decentralized savings vault on OPN Chain.

DeBank lets you deposit IOPN, stablecoins, and other OPN Chain assets into a self-custodied on-chain vault, choose your own unlock date, and withdraw when you're ready. The discipline is built in — your funds stay locked until maturity, with an early exit always available for a small fee so you're never completely blocked.


Live App
**________________**


# Deployed Contract

FieldValueNetworkOPN Chain Testnet (Chain ID 984)Contract address0x67Fecd16CdEA7da4005a6eb21dbC00Fc5De11041 
ExplorerView on testnet.iopn.tech


# What DeBank does

Lock any duration — from 1 day to 5 years, chosen by the depositor
Top up existing locks — add more IOPN to a lock before it matures
Withdraw at maturity — small claim fee, full principal returned
Early withdrawal — always available for a larger fee, never permanently locked
Multi-asset support — native IOPN live now; USDC and USDT support built in, activates as those tokens launch on OPN Chain
Non-custodial — only the depositor's wallet can ever withdraw their funds; owner-only functions are limited to fee settings and an ERC-20 allow-list, with a hard 5% ceiling on any fee
Pause safety — the contract can be paused to block new deposits, but withdrawals always remain open



# Repository structure

debank/
├── contracts/
│   ├── TimeLockVault.sol       # Main vault contract
│   └── mocks/
│       └── MockERC20.sol       # Fake token used in local tests only
├── test/
│   └── TimeLockVault.test.js   # 10 automated tests (all passing)
├── scripts/
│   └── deploy.js               # Deployment script for OPN testnet
├── site/
│   ├── index.html              # Landing page (Aurora hero, features, testimonials)
│   └── app.html                # The app (sidebar, vault, chart, history)
├── hardhat.config.js
├── package.json
├── .env.example
└── .gitignore


# Running locally

Prerequisites

Node.js 18 or higher
A MetaMask wallet (create a fresh one for this — do not use a wallet holding real funds)


Setup

bashnpm install
cp .env.example .env

Open .env and paste your throwaway wallet's private key after PRIVATE_KEY=.

Compile

bashnpx hardhat compile

Run tests

bashnpx hardhat test

All 10 tests should pass. They cover: normal lock and claim, early withdrawal fee, top-up, reentrancy guard, cross-wallet claim rejection, pause behaviour, fee ceiling enforcement, and double-claim prevention.

Deploy to OPN Testnet

bashnpx hardhat run scripts/deploy.js --network opnTestnet

Get test IOPN from the faucet at faucet.iopn.tech before deploying.


Frontend

The frontend is two plain HTML files with no build step required — just open them in a browser or deploy to any static host.


index.html — landing page with an Aurora WebGL background, feature overview, supported assets, how it works, and user testimonials
app.html — the full app: collapsible sidebar, dashboard with real on-chain savings chart, deposit form, lock management, transaction history, and Arkive (coming soon)


Wallets supported: MetaMask, OKX, Coinbase Wallet, Rabby.


Tech stack

LayerTechnologySmart contractSolidity 0.8.24, OpenZeppelin 5TestsHardhat, Ethers.js v6, ChaiFrontendVanilla HTML/CSS/JSWeb3Ethers.js v6 (CDN)ChartChart.js 4 (CDN)BackgroundOGL WebGL (Aurora shader)FontPlus Jakarta SansNetworkOPN Chain Testnet


Security notes


No admin function can move a user's locked principal
Fees are capped at 5% (500 bps) by the contract — cannot be exceeded
Pausing blocks new deposits but never blocks withdrawals
Each lock's owner is stored on-chain and verified at claim time — cross-wallet theft is impossible by design
MockERC20 is used only in local tests and is never deployed on testnet or mainnet


This is a testnet deployment built for the IOPn Builders Programme Season 1. Before any mainnet deployment holding real value, an independent audit is strongly recommended.


Built for

IOPn Builders Programme — Season 1
