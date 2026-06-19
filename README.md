<div align="center">

# ⧗ DeBank

### A Decentralized savings vault on OPN Chain

**Deposit. Lock. Withdraw on your terms.**

[![Live App](https://img.shields.io/badge/Live%20App-iopn--debank.netlify.app-7cff67?style=for-the-badge&logo=netlify&logoColor=black)](https://iopn-debank.netlify.app/)
[![Network](https://img.shields.io/badge/Network-OPN%20Chain%20Testnet-5227FF?style=for-the-badge)](https://testnet.iopn.tech)
[![Built For](https://img.shields.io/badge/Built%20For-IOPn%20Builders%20Programme-B497CF?style=for-the-badge)](https://builders.iopn.tech)

</div>

---

## What is DeBank?

DeBank is a non-custodial, Decentralized savings vault built on OPN Chain. Users deposit **IOPN** (and soon USDC, USDT, and other OPN Chain assets) into a smart contract, set their own unlock date, and walk away knowing their funds are safe until they're ready.

The discipline is built in by design — your assets stay locked until maturity. An emergency exit is always available for a small fee, so you're never permanently blocked from your own money.

> _"I locked 500 IOPN before a bull run and couldn't touch it even when panic hit. Best financial decision I've made on any chain."_ — Paul Atkins, Crypto Trader

---

##  Key Links

| | |
|---|---|
|  **Live App** | https://iopn-debank.netlify.app/ |
|  **Contract Address** | `0x67Fecd16CdEA7da4005a6eb21dbC00Fc5De11041` |
|  **Explorer** | [View on OPN Testnet Explorer](https://testnet.iopn.tech/address/0x67Fecd16CdEA7da4005a6eb21dbC00Fc5De11041) |
|  **Network** | OPN Chain Testnet · Chain ID `984` |
|  **Builder Programme** | [builders.iopn.tech](https://builders.iopn.tech) |

---

##  Features

-  **Time-lock discipline** — Choose your unlock date from 1 day to 5 years
-  **Top-up anytime** — Add more IOPN to an existing lock before it matures
-  **Emergency exit** — Early withdrawal is always available for a transparent fee — you're never fully locked out
-  **Full history** — On-chain transaction history with deposit and withdrawal tracking
-  **Savings chart** — Live line chart built from your real on-chain event data
-  **Multi-wallet support** — MetaMask, OKX Wallet, Coinbase Wallet, Rabby
-  **Non-custodial** — Only your wallet key can ever withdraw your funds
-  **Pause safety** — Contract can be paused to halt new deposits, but withdrawals always remain open
-  **Arkive** _(coming soon)_ — Store physical assets on-chain

---

##  Supported Assets

| Token | Status |
|---|---|
| **IOPN** (Native) |  Live |
| **USDC** |  Coming soon |
| **USDT** |  Coming soon |
| Other OPN ERC-20s |  Expanding |

---

## 🖥️ App Overview

The frontend is two plain HTML files — no build step, no framework, no complexity. Drag both onto [Netlify](https://netlify.com) and it works.

### Landing Page (`index.html`)
- Aurora WebGL background (OGL shader)
- Feature overview, asset support section
- Step-by-step how-it-works
- User testimonials

### App (`app.html`)
- Collapsible sidebar navigation
- **Dashboard** — 4 live stat cards + real savings line chart (Chart.js, built from on-chain events)
- **The Vault** — Deposit form with duration chips, live net preview, lock cards with top-up and withdrawal
- **Arkive** — Coming soon page
- **History** — Full deposit and withdrawal event log with timestamps
- **Settings** — Network status and contract info

---

##  Tech Stack

| Layer | Technology |
|---|---|
| Smart Contract | Solidity `0.8.24` · OpenZeppelin 5 |
| Testing | Hardhat · Ethers.js v6 · Chai (10/10 tests passing) |
| Frontend | Vanilla HTML / CSS / JS |
| Web3 | Ethers.js v6 (CDN) |
| Chart | Chart.js 4 (CDN) |
| Background | OGL WebGL (Aurora GLSL shader) |
| Font | Plus Jakarta Sans |
| Network | OPN Chain Testnet (Chain ID 984) |

---

## 📁 Repository Structure

```
debank/
├──  README.md
├──   hardhat.config.js
├──  package.json
├──  .env.example
├──  .gitignore
│
├── 📂 contracts/
│   ├── TimeLockVault.sol        ← Main vault contract
│   └── mocks/
│       └── MockERC20.sol        ← Local test token (not deployed)
│
├── 📂 test/
│   └── TimeLockVault.test.js    ← 10 automated tests
│
├── 📂 scripts/
│   └── deploy.js                ← OPN testnet deployment
│
└── 📂 site/
    ├── index.html               ← Landing page
    └── app.html                 ← Full app
```

---

##  Smart Contract

**Contract:** `DeBank.sol`

```
Address:   0x67Fecd16CdEA7da4005a6eb21dbC00Fc5De11041
Network:   OPN Chain Testnet
Chain ID:  984
RPC:       https://testnet-rpc.iopn.tech
```

### Core Functions

| Function | Description |
|---|---|
| `createLock(token, amount, duration)` | Deposit and lock assets for a chosen duration |
| `topUp(lockId, amount)` | Add more to an existing lock |
| `claim(lockId)` | Withdraw a matured lock (normal fee) |
| `claim(lockId)` before unlock | Early withdrawal (higher fee) |
| `getUserLockIds(address)` | Get all lock IDs for a wallet |
| `getLock(lockId)` | Read a single lock's data |

### Fee Structure

| Action | Fee |
|---|---|
| Deposit | 0.5% |
| Withdraw at maturity | 0.5% |
| Early withdrawal | 2.0% |
| Maximum possible fee | 5.0% (hard-coded ceiling) |

---

## 🛡️ Security Design

- ✅ **No admin access to user funds** — owner-only functions are limited to fee settings and ERC-20 allow-list
- ✅ **Fee ceiling enforced on-chain** — cannot exceed 5% regardless of owner calls
- ✅ **Owner verified at claim time** — cross-wallet theft is impossible by contract logic
- ✅ **Reentrancy guard** — OpenZeppelin `ReentrancyGuard` applied to all state-changing functions
- ✅ **Pause never blocks withdrawals** — users can always exit, even during a pause
- ✅ **Double-claim prevention** — claimed locks are flagged and reject further attempts


## ✅ Test Results

```
TimeLockVault
  ✔ deploys with correct initial state
  ✔ creates a lock and stores correct data
  ✔ allows the owner to top up a lock
  ✔ allows claim after unlock time (normal fee)
  ✔ allows early claim with higher fee
  ✔ rejects claim by non-owner wallet
  ✔ rejects double-claim on same lock
  ✔ rejects fees above the 5% ceiling
  ✔ blocks new locks when paused, allows claim
  ✔ rejects lock duration outside allowed range

10 passing
```

Built on OPN Chain · Season 1 · 2026

⧗

</div>
