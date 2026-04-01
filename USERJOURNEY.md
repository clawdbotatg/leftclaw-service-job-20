# USERJOURNEY.md — TreasuryManager V2 Staking Integration (Job 20)

## Overview

This document describes the step-by-step user journey for the TreasuryManager V2 staking integration. The primary actor is the **AMI Operator** (the wallet assigned as operator), who manages the treasury's ₸USD positions through staking.

## Actors

- **AMI Operator**: Controls staking/unstaking, buybacks, burns, rebalancing. Has a configured operator wallet.
- **Owner**: Can change operator, update caps, set slippage. The owner is the client wallet.
- **Permissionless User**: Anyone can call `permissionlessRebalance` — no special role needed.

---

## Happy Path — Stake ₸USD

### Step 1: Connect Wallet
- User lands on TreasuryManager V2 dashboard
- Clicks "Connect Wallet"
- MetaMask / WalletConnect popup appears
- User approves

### Step 2: Verify Operator Status
- Dashboard reads `isOperator(msg.sender)` from contract
- If not operator: shows "Operator access required" — only staking pool data visible
- If operator: full dashboard unlocks

### Step 3: View Pool Options
- Frontend fetches available pool IDs from staking contract
- Displays pool list with estimated APY (if available from staking contract)
- Operator selects target pool from dropdown

### Step 4: Enter Stake Amount
- Operator enters amount of ₸USD to stake
- Frontend shows:
  - Current ₸USD balance
  - Amount being staked
  - Estimated pool share after staking
  - Transaction preview

### Step 5: Approve ₸USD (if needed)
- If `allowance(operator, treasuryManager) < amount`:
  - "Approve" button appears (only button shown — no Execute yet)
  - Operator clicks "Approve"
  - MetaMask pops up for approval tx
  - Button disabled during pending tx
- Once approved: "Stake" button appears

### Step 6: Execute Stake
- Operator clicks "Stake"
- MetaMask popup for `stake(amount, poolNumber)` tx
- Spinner + disabled button during pending
- On confirmation: success toast, balance updates

### Step 7: Verify
- User's staked position updates in staking contract view
- `StakeExecuted` event appears in transaction history

---

## Happy Path — Unstake ₸USD

### Step 1: Connect Wallet (if not already connected)

### Step 2: Select Pool to Unstake
- Dropdown shows pools where operator has a balance
- Selecting pool fetches: staked amount + estimated rewards from staking contract

### Step 3: Review Unstake
- Shows: staked amount + rewards to be withdrawn
- Note: unstake withdraws FULL balance — no partial unstake
- Shows transaction preview

### Step 4: Execute Unstake
- "Unstake" button (no approval needed — staking contract pulls from TM)
- MetaMask popup for `unstake(poolNumber)` tx
- On confirmation: success toast, position cleared

---

## Happy Path — Buyback with WETH

### Step 1: Operator enters WETH amount
- Input field: "WETH Amount"
- Shows: operator's WETH balance, current ₸USD price from TWAP

### Step 2: Check Caps
- Frontend reads `operatorDailyUsed` and `operatorDayStart` from contract
- If `block.timestamp - operatorDayStart > 24 hours`: usage reset shown as $0 / $2 ETH
- Warns if amount would exceed daily cap

### Step 3: Check Cooldown
- Reads last action timestamp
- If < 60 minutes ago: shows countdown timer, button disabled

### Step 4: Execute Buyback
- "Buyback" button appears (only button)
- On click: `buybackWithWETH(amount)` call
- Shows spinner during tx
- On success: ₸USD balance increases, WETH decreases

---

## Happy Path — Permissionless Rebalance (Anyone)

### Step 1: Any user views dashboard
- Does NOT require wallet connection to view state
- Shows current ROI vs unlock threshold
- Shows ₸USD unlock % based on ROI + time

### Step 2: User verifies unlock conditions
- ROI ≥ 1000% check displayed (with current ROI calculation)
- 14-day inactivity check displayed
- Circuit breaker status shown

### Step 3: User executes rebalance
- User connects any wallet
- Enters token + amount
- Provides paths (or uses auto-computed paths)
- Executes `permissionlessRebalance(token, amount, pathToWETH, pathToUSDC)`
- 75% → ₸USD, 25% → designated address (shown in UI)

---

## Edge Cases

### Wrong Network
- If user is not on Base: "Switch to Base" button shown
- Only that button shown — no other actions accessible

### Insufficient Balance
- If WETH amount > operator's WETH balance: button disabled, "Insufficient WETH" shown
- Same for ₸USD staking vs ₸USD balance

### Cooldown Active
- If 60-min cooldown not elapsed since last operator action:
  - "Next action available in X:XX" countdown timer
  - All action buttons disabled
  - Exact unlock timestamp shown

### Daily Cap Exceeded
- If daily cap (2 ETH) would be exceeded:
  - Shows remaining: "0.3 ETH remaining of 2 ETH daily cap"
  - Button disabled with "Daily cap reached" label
  - Shows reset time (when 24h window expires)

### Circuit Breaker Triggered
- If ₸USD spot > 15% above 24h TWAP:
  - All permissionless rebalance buttons disabled
  - Shows: "Circuit breaker active — ₸USD price elevated"
  - Explains: protection against sandwich attacks

### ROI Below Unlock Threshold
- If ROI < 1000%: shows current ROI %, progress toward 1000%
- Stake/unstake still works (unlock is for SELLING/REBALANCING unlocked tokens)
- Explanation shown in UI

### Pool Not Found (Unstake)
- If operator selects a pool with 0 balance: warning shown
- "Unstake" button still available (will withdraw 0 + any future rewards)

### Stale Pool Index (bot — V4 only)
- If forced poolId provided but not in local index:
  - Bot fails fast with error
  - Logs: "Pool {poolId} not found in index"
  - No silent fallback

### RPC Timeout (bot)
- If quote call exceeds 5s: timeout error shown
- Bot retries with exponential backoff
- Max 3 retries before failing with clear error

---

## Dashboard Layout (Suggested)

```
┌─────────────────────────────────────────────────────────┐
│  🏦 ₸USD Treasury Manager — Operated by AMI            │
│  Network: Base ✓ | Wallet: 0x...1234 [disconnect]       │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  [STAKING]  [BUYBACK]  [BURN]  [REBALANCE]  [PERMISSIONSLESS] │
│                                                         │
│  ┌─ STAKING ─────────────────────────────────────────┐ │
│  │ Pool: [▼ Select Pool]                             │ │
│  │ Your staked: 50,000 ₸USD (Pool 3)                 │ │
│  │ Est. rewards: 1,234 ₸USD                          │ │
│  │                                                  │ │
│  │ Amount: [________] ₸USD  (Balance: 120,000)      │ │
│  │                                                  │ │
│  │ [STAKE ₸USD]           [UNSTAKE]                  │ │
│  └──────────────────────────────────────────────────┘ │
│                                                         │
│  ┌─ CAPACITY ────────────────────────────────────────┐ │
│  │ Daily cap: 0.8 / 2.0 ETH                          │ │
│  │ Resets in: 4h 23m                                 │ │
│  │ Cooldown: Ready now ✓  /  14h 12m until unlock   │ │
│  └──────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

---

## Contract Addresses

| Contract | Address |
|----------|---------|
| TreasuryManager v2 | TBD (deploy) |
| Staking Contract | `0x2a70a42BC0524aBCA9Bff59a51E7aAdB575DC89A` |
| ₸USD | TBD (confirm from client) |
| WETH | `0x4200000000000000000000000000000000000006` |
| USDC | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` |
| Universal Router | `0x6fF5693b99212Da76ad316178A184AB56D299b43` |
| PoolManager | `0x498581ff718922c3f8e6a244956af099b2652b2b` |
| V4 Quoter | `0x0d5e0F971ED27FBfF6c2837bf31316121532048D` |

## Client (Owner)

`0x9ba58Eea1Ea9ABDEA25BA83603D54F6D9A01E506`
