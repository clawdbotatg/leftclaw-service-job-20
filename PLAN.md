# PLAN.md — TreasuryManager V2: Staking Integration Build

## Job ID: 20
## Client: 0x9ba58Eea1Ea9ABDEA25BA83603D54F6D9A01E506
## Chain: Base (8453)

---

## Overview

TreasuryManager V2 is an onchain treasury management system for ₸USD (TurboUSD) on Base, operated by AMI. It enforces strictly one-directional token flows: ERC20s are bought with ETH/WETH, accumulated, then rebalanced back into ₸USD (75%) and USDC to owner (25%). ₸USD can only be bought, staked, burned — never sold. Three independent permissionless fallback paths guarantee treasury funds are never stuck. Deployed as a 3-contract system to stay within the 24KB contract size limit.

## Clarifications (confirmed by client)

1. **initialBalanceSnapshot**: Dynamic — taken at first interaction, updates on every new buy. `snapshot += newBuyAmount`. Unlock % calculated against `currentBalance` (which includes new buys).

2. **buyTokenWithETH(address token, uint256 amount, uint256 poolNumber)**: `amount` = WETH INPUT (exactInput style — how much ETH/WETH to spend). `poolNumber` = staking pool ID.

3. **Daily cap reset**: Rolling 24-hour window from `block.timestamp`. If `block.timestamp - dayStart > 24 hours`: reset usage to 0, set new dayStart. NOT calendar-aligned.

## Architecture

### Contract 1: TreasuryManager.sol (Core)
- State storage, access control, cap enforcement
- Owner/Operator/Permissionless function entry points
- Delegates swap execution to SwapHelper library
- Delegates unlock path calculations to PermissionlessModule library

### Contract 2: SwapHelper.sol (Library)
- Pure library, no state, delegatecall only
- Handles all Uniswap Universal Router interactions (V3 + V4)
- 3-leg atomic rebalance (token→WETH→25% USDC to owner + 75% ₸USD)
- Buyback execution (WETH/USDC → ₸USD)
- BuyToken execution (WETH → ERC20)

### Contract 3: PermissionlessModule.sol (Library)
- Pure library, no state, delegatecall only
- Path 1: ROI-based unlock (1000% threshold, 25% base + 5% compounding tranches)
- Path 2: Market cap-based unlock ($100M threshold, 20% base + 5% flat tranches)
- Path 3: Emergency drip (180-day trigger, then 5% every 60 days)
- Oracle reads (Chainlink ETH/USD + USDC/WETH fallback)
- Spot price reads (V3 slot0 + V4 getSlot0)

## Key Features

### Dynamic Snapshot Tracking
- `initialBalanceSnapshot[token]` set on first interaction
- Updated on every `buyTokenWithETH`: `snapshot += newBuyAmount`
- Unlock % calculated against current token balance (accounts for new buys)

### buyTokenWithETH with WETH Input + poolNumber
- `buyTokenWithETH(address token, uint256 amount, uint256 poolNumber)`
- `amount` = WETH to spend (exactInput semantics)
- `poolNumber` = index into registered pools for that token
- Operator-only, uncapped, tracks cost basis

### Rolling 24h Daily Cap Windows
- `operatorDayStart[capKey]` tracks when current window started
- On each action: if `block.timestamp - dayStart > 24 hours`, reset usage to 0 and set new dayStart
- Same pattern for permissionless per-token caps

### Staking Integration
- `stake(uint256 amount, uint256 poolId)` — deposit ₸USD to staking contract
- `unstake(uint256 amount, uint256 poolId)` — withdraw ₸USD from staking
- Uses ₸USD Staking Contract at 0x2a70a42BC0524aBCA9Bff59a51E7aAdB575DC89A
- `deposit(uint256 _amount, uint256 poolId)` selector: 0xe2bbb158
- `withdraw(uint256 _amount, uint256 poolId)` selector: 0x441a3e70

### Permissionless Rebalance (3 paths)
- Path 1: ROI ≥ 1000% + 14-day inactivity
- Path 2: Market cap ≥ $100M + 14-day inactivity
- Path 3: Emergency drip after 180 days inactivity
- Immutable caps: 0.5 ETH/action, 2 ETH/day, 3% slippage, 4h cooldown
- Ratchet: unlock % only goes up, never down

## Hardcoded Addresses (Base)
- TUSD: 0x3d5e487B21E0569048c4D1A60E98C36e1B09DB07
- TUSD_POOL: 0xd013725b904e76394A3aB0334Da306C505D778F8
- USDC: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
- WETH: 0x4200000000000000000000000000000000000006
- STAKING: 0x2a70a42BC0524aBCA9Bff59a51E7aAdB575DC89A
- Chainlink ETH/USD: verified on Base at build time
- Universal Router: verified on Base at build time
- USDC/WETH pool: verified canonical 0.05% V3 pool on Base
- V4 PoolManager: Uniswap V4 singleton on Base

## Stack
- Solidity 0.8.26
- Foundry (forge test, fuzz, fork tests against Base)
- Scaffold-ETH 2 (frontend)
- Uniswap Universal Router (V3 + V4 swaps)
- Chainlink ETH/USD oracle
- IPFS deployment via bgipfs

## Security
- ReentrancyGuard on every external-calling function
- CEI pattern throughout
- Balance deltas for all token accounting (fee-on-transfer safe)
- Output validation after every swap hop
- Chainlink staleness check (1 hour)
- Ownable2Step for safe ownership transfer
- Immutable permissionless parameters (owner can't change)
- Multiply before divide (no precision loss)
