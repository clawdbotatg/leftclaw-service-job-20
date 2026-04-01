# USERJOURNEY.md — TreasuryManager V2

## Actors

1. **Owner** (client: 0x9ba58Eea1Ea9ABDEA25BA83603D54F6D9A01E506) — full control, bypasses caps
2. **Operator** — daily operations with caps & cooldowns
3. **Anyone** (permissionless) — rebalance with immutable constraints

---

## Happy Paths

### Owner: Set Up Treasury
1. Owner deploys TreasuryManager → owner = msg.sender
2. Owner calls `setOperator(operatorAddress)` to assign operator
3. Owner calls `registerToken(tokenAddr, v3Pool, v4PoolId, isV4)` for each token to track
4. Owner optionally calls `appendPool(token, ...)` to add additional swap pools
5. Owner sends ETH to the contract (receives via `receive()`)

### Operator: Buy Tokens with ETH
1. Operator calls `buyTokenWithETH(tokenAddr, wethAmount, poolNumber)` with `msg.value = wethAmount`
2. Contract wraps ETH → WETH, swaps through registered pool
3. Tokens received are tracked: `totalWeiSpent[token] += wethAmount`, `totalTokensReceived[token] += received`
4. `initialBalanceSnapshot[token]` is updated: `snapshot += received` (dynamic snapshot)
5. Event `BuyToken(token, wethSpent, tokensReceived, poolNumber, caller)` emitted

### Operator: Buyback ₸USD
1. Operator calls `buybackWithWETH(amountIn)` — WETH → ₸USD swap
2. Contract checks operator caps (per-action + daily) with rolling 24h window
3. Contract checks 60-min cooldown since last operator action
4. Swap executes through ₸USD V3 pool
5. ₸USD stays in contract

### Operator: Stake ₸USD
1. Operator calls `stake(amount, poolId)`
2. Contract checks STAKE caps and cooldown
3. Contract approves staking contract for ₸USD amount
4. Calls `staking.deposit(amount, poolId)`
5. Event `Stake(amount, poolId, caller)` emitted

### Operator: Unstake ₸USD
1. Operator calls `unstake(amount, poolId)`
2. No caps, no cooldown (unrestricted withdrawal)
3. Calls `staking.withdraw(amount, poolId)`
4. ₸USD returns to TreasuryManager
5. Event `Unstake(amount, poolId, caller)` emitted

### Operator: Rebalance Token → ₸USD
1. Operator calls `rebalance(token, amount, poolNumber)`
2. Contract checks ROI or Market Cap gates (no inactivity required for operator)
3. Contract checks caps, cooldown, unlock limits
4. Atomic 3-leg swap: Token → WETH → 25% USDC to owner + 75% WETH → ₸USD
5. If meaningful (≥2% of balance): updates inactivity timestamp, resets Path 3 drip

### Permissionless: Rebalance
1. Anyone calls `permissionlessRebalance(token, amount, poolNumber)`
2. Contract checks:
   - Token is registered
   - 4-hour per-token cooldown passed
   - Daily cap (2 ETH/day per token, rolling 24h window)
3. Snapshot taken if first interaction
4. All 3 unlock paths evaluated, max taken, ratcheted up
5. Amount must be within unlocked allowance minus already-rebalanced
6. Same 3-leg atomic swap with 3% slippage
7. Post-swap: WETH received ≤ 0.5 ETH checked
8. Path 3 drip timer reset

### Owner: Emergency Overrides
1. `ownerRebalance(token, amount, poolNumber)` — bypasses caps/cooldown/ROI/mcap gates
2. `ownerBuybackWithWETH(amountIn)` — bypasses caps/cooldown
3. `ownerBuybackWithUSDC(amountIn)` — bypasses caps/cooldown
4. `transferOwnership(newOwner)` — two-step Ownable2Step

---

## Edge Cases

### Wrong Network
- User connects to wrong chain → frontend shows "Switch to Base" button
- All contract interactions fail gracefully with wrong chain

### Insufficient Balance
- Operator tries buyback with insufficient WETH → reverts with clear error
- Operator tries stake with insufficient ₸USD → reverts

### Cooldown Not Passed
- Operator tries action within 60 min of last → reverts "Cooldown active"
- Permissionless tries within 4 hours of last for same token → reverts

### Cap Exceeded
- Operator exceeds per-action cap → reverts "Exceeds per-action cap"
- Operator exceeds daily cap → reverts "Exceeds daily cap"
- Rolling 24h window: if 24 hours passed since dayStart, usage resets automatically

### No Unlock Path Valid
- Permissionless rebalance when no path qualifies → reverts "No unlock path valid"
- ROI below 1000% AND market cap below $100M AND Path 3 not triggered

### Slippage Exceeded
- Any swap hop receives less than minimum → entire tx reverts "Slippage exceeded"
- Zero output on any hop → reverts "Zero output"

### Oracle Failure
- Chainlink stale (>1 hour) → falls back to USDC/WETH pool price
- Both fail → reverts (no silent fallback to bad data)

### No Wallet Connected
- Frontend shows "Connect Wallet" button (not text)
- All action buttons hidden until connected + correct network

---

## Frontend Flow

### Four-State Button
```
1. Not connected  → Connect Wallet button
2. Wrong network  → Switch to Base button
3. Needs approval → Approve button (if token approval needed)
4. Ready          → Action button (Buy/Stake/Rebalance/etc.)
```

### Dashboard
- Contract ETH/WETH balance
- ₸USD balance (in contract + staked)
- All registered tokens with balances
- Cost basis per token (avg cost, current price, ROI)
- Unlock percentages per token (all 3 paths)
- Operator caps status (used/remaining)
- Recent events

### Admin Panel (Owner only)
- Set operator
- Register/append token pools
- Update operator caps
- Update slippage
- Owner overrides (buyback, rebalance)
- Transfer ownership
