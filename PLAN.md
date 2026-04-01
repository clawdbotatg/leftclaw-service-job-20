# PLAN.md — TreasuryManager V2 Staking Integration (Job 20)

## Overview

TreasuryManager V2 is an onchain treasury management contract for ₸USD (TurboUSD) on Base, operated by AMI (Artificial Monetary Intelligence). This job (Job 20) is the staking integration build — primary focus on the staking UI flow and integration with the ₸USD staking contract.

The contract itself follows the same spec as TreasuryManager v2 (same as job 9). This job delivers the staking integration features: `stake()` and `unstake()` functions with a staking-focused frontend.

## What Was Confirmed By Client (from job messages)

1. **`initialBalanceSnapshot` behavior**: Dynamic. Updates on every new buy. `snapshot += newBuyAmount`. Unlock % always calculated against `currentBalance` (which already reflects new buys). This means buys increase how much can be sold proportionally — the cap scales with what the operator actually holds.

2. **`buyTokenWithETH(address token, uint256 amount, uint256 poolNumber)` signature confirmed**: `amount` = WETH to spend (input amount, exactInput style). The `poolNumber` (poolId) is used for staking pool selection.

3. **Daily cap reset**: Rolling 24-hour window from `block.timestamp`, not calendar-aligned.
   ```solidity
   if (block.timestamp - operatorDayStart[operator] > 24 hours) {
       operatorDailyUsed[operator] = 0;
       operatorDayStart[operator] = block.timestamp;
   }
   ```

## Smart Contract — TreasuryManager V2

### Immutable State
- WETH: `0x4200000000000000000000000000000000000006`
- USDC: `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`
- ₸USD: `0xCb8d2C6229FA4a7D96B242345551E562e0e2FC76` (to confirm from client)
- Official ₸USD/WETH Uniswap V3 pool (to confirm from client)
- Staking contract: `0x2a70a42BC0524aBCA9Bff59a51E7aAdB575DC89A`
- Universal Router: `0x6fF5693b99212Da76ad316178A184AB56D299b43`
- PoolManager: `0x498581ff718922c3f8e6a244956af099b2652b2b`
- V4 Quoter: `0x0d5e0F971ED27FBfF6c2837bf31316121532048D`

### Permissionless Constants (hardcoded, never changeable)
- 3% slippage
- 4h cooldown (permissionless)
- 5% max per swap of unlocked
- 15% circuit breaker vs 24h TWAP
- 14-day operator inactivity period
- 90-day dead pool threshold
- 60-min operator cooldown
- 0.5 ETH per action cap
- 2 ETH per day cap

### Operator Caps (owner-configurable)
- BuybackWETH: 0.5 ETH/action, 2 ETH/day
- BuybackUSDC: 2000/action, 5000/day
- Burn: 100M ₸USD/action, 500M/day
- Stake: 100M ₸USD/action, 500M/day
- Rebalance: uses BuybackWETH caps on 100% of input

### Owner-Only Functions
- `setOperator(address)` — set AMI operator
- `updateCaps(ActionType, perAction, perDay)` — change operator caps
- `setSlippage(uint256 bps)` — operator slippage only
- `rescueDeadPoolToken(address token, bytes path)` — only after 90+ days of dead pool

### Operator-Only Functions
- `buybackWithWETH(uint256 amountIn)` — WETH → ₸USD via official pool. BuybackWETH caps. 60-min cooldown.
- `buybackWithUSDC(uint256 amountIn)` — USDC → WETH → ₸USD via official pool. BuybackUSDC caps. 60-min cooldown.
- `burn(uint256 amount)` — partial burn of ₸USD. Burn caps. 60-min cooldown.
- `stake(uint256 amount, uint256 poolNumber)` — deposit ₸USD to staking contract. Stake caps. 60-min cooldown. `poolNumber` selects the poolId in the staking contract.
- `unstake(uint256 poolNumber)` — withdraw full balance + rewards from staking pool. No caps, no cooldown.
- `buyTokenWithETH(address token, uint256 amount, bytes path)` — ETH → ERC20 via Universal Router. `amount` = WETH to spend. Path validated starts with WETH. Records cost basis via balanceOf delta.
- `rebalance(address token, uint256 amount, bytes pathToWETH, bytes pathToUSDC)` — 75% → WETH → ₸USD via official pool (stays in contract). 25% → USDC to designated address. BuybackWETH caps on full input. 60-min cooldown.

### Permissionless Function
- `permissionlessRebalance(address token, uint256 amount, bytes pathToWETH, bytes pathToUSDC)` — anyone can call. Guarantees ₸USD buybacks continue regardless of operator status.

**Unlock Conditions (both required):**
1. ROI ≥ 1000% vs weighted average cost, measured via 24h TWAP from token's Uniswap pool
2. No operator rebalance for 14 days since current ROI tier was first reached

**Unlock Schedule (ratcheted, never decreases):**
- 1000% ROI: 25% unlocked
- Each additional 10% above: 5% of remaining locked unlocks

**Execution Rules:**
- Max 5% of unlocked per tx
- 4h cooldown per token
- Circuit breaker: ₸USD spot vs 24h TWAP from official pool, blocks if spot >15% above TWAP
- Hardcoded caps: 0.5 ETH/action, 2 ETH/day
- Hardcoded 3% slippage
- Path validated

## Architecture Decisions

### Dynamic Balance Snapshot
The `initialBalanceSnapshot` is NOT static. Every time a new buy for a token occurs:
```
snapshot = snapshot + newBuyAmount
```
The unlock percentage is always computed against `currentBalance`, which already reflects new buys. This means buys increase how much can be sold proportionally.

### Staking Pool Discovery
`poolNumber` in `stake()` and `unstake()` corresponds directly to `poolId` in the staking contract at `0x2a70a42BC0524aBCA9Bff59a51E7aAdB575DC89A`. The frontend should display available pools and let the operator select one.

### Cost Basis Tracking
Only tracks tokens bought via `buyTokenWithETH`. Unsolicited transfers are ignored. Cost basis computed via `balanceOf` deltas (handles fee-on-transfer and rebasing tokens).

### Daily Cap — Rolling Window
Rolling 24-hour window from `block.timestamp` of first action in period. When window expires, usage resets to 0 and new window starts.

## Frontend — Staking Integration Focus

The UI should prioritize:
1. **Staking panel** — select pool, enter amount, stake ₸USD
2. **Unstake panel** — select pool, view estimated rewards, unstake full balance
3. **Pool discovery** — fetch available poolIds from staking contract
4. **Operator dashboard** — view caps, cooldowns, daily usage

Standard TM v2 panels (buyback, burn, rebalance) are secondary.

## Tech Stack

- **Contracts:** Foundry
- **Frontend:** Scaffold-ETH 2 (Next.js)
- **Network:** Base mainnet (chain 8453)
- **UI library:** Scaffold-ETH UI components + custom staking components

## Client Wallet (Owner/Admin)

`0x9ba58Eea1Ea9ABDEA25BA83603D54F6D9A01E506`

All constructor args, `transferOwnership`, `setOperator` calls must use this address. Never hardcode — read from job data.

## Build Pipeline

1. `create_repo` ✅ (done)
2. `create_plan` ← THIS FILE
3. `create_user_journey`
4. `prototype` (Phase 1: local fork, Phase 2: live contracts + local UI, Phase 3: IPFS)
5. `contract_audit`
6. `contract_fix`
7. `deep_contract_audit` (if complex)
8. `deep_contract_fix`
9. `frontend_audit`
10. `frontend_fix`
11. `full_audit`
12. `full_audit_fix`
13. `deploy_contract`
14. `livecontract_fix`
15. `deploy_app`
16. `liveapp_fix`
17. `liveuserjourney`
18. `readme`
19. `ready`

## ethskills.com

Follow https://ethskills.com exactly. Fetch relevant skills before each stage.
