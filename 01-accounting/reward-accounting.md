# Reward Accounting in YieldCore

## 1. Title
Reward Accounting in YieldCore

## 2. Overview
YieldCore rewards are per-stake, fixed-rate, and time-proportional, with accrual capped at `MAX_REWARD_TIME = 1 day`. Rewards are paid from a shared `rewardPool` balance funded by owner deposits and augmented by early-unstake penalties.

## 3. Exact YieldCore Accounting Mechanics
Per stake fields:
- `amount`
- `startTime`
- `lockPeriod`
- `fixedRate`
- `rewardsClaimed`
- `active`, `expired`

Core reward formula in `calculateReward`:
- If inactive/expired/past grace expiry => `0`.
- `timeElapsed = min(block.timestamp - startTime, 1 day)`.
- `totalEarned = amount * fixedRate * timeElapsed / (100 * 1 day)`.
- claimable = `max(totalEarned - rewardsClaimed, 0)`.

Implication: rewards stop increasing after one day from `startTime`, independent of longer lock periods.

## 4. Function-by-Function Reward-Accounting Review (All Public Functions)
1. `setLockParameters`: Sets future `fixedRate` only at stake creation; historical stakes keep prior rates.
2. `fundRewardPool`: Increases reward solvency but does not verify projected liabilities.
3. `stake`: Snapshots rate into `fixedRate`; no liability reservation is created on entry.
4. `calculateReward`: Uses fixed `startTime` (not last-claim timestamp), compensated by `rewardsClaimed` subtraction.
5. `claimReward`: Deducts from `rewardPool`; reverts if pool underfunded.
6. `unstake`: If lock expired, pays principal + remaining reward; if early, applies penalty and recycles penalty into `rewardPool`.
7. `cleanUpExpiredStake`: Changes reward eligibility indirectly by setting `expired`.
8. `emergencyWithdraw`: Returns principal only while paused; reward entitlement is effectively abandoned.
9. `withdrawExcessRewards`: Can alter available liquidity and perceived solvency under paused mode.
10. `maxReward`: Returns `amount * fixedRate / 100`; aligns with 1-day cap design.
11. `getStakeCount`: View.
12. `getStake`: View.
13. `getRewardsClaimed`: View.
14. `getContractBalance`: View.
15. `pause`: Accounting halted for most user actions.
16. `unpause`: Resumes flows.

## 5. Fixed-Rate-per-Stake vs `accRewardPerShare`
### Current fixed-rate model strengths
- Easy to reason about per user.
- No global accumulator drift complexity.

### Weaknesses
- No global notion of emission budget over time.
- Solvency depends on owner operations and penalty recycling.
- Different cohorts may face payout failures if rewardPool lags liabilities.

### `accRewardPerShare` alternative
- Defines deterministic emission per block/second distributed by share.
- Improves fairness under dynamic participation.
- Easier to prove conservation invariants.

Tradeoff:
- More complex checkpoint logic and update scheduling.

## 6. Fairness of the 1-Day Reward Cap
The 1-day cap simplifies risk but can be economically unintuitive:
- Long lock periods do not produce proportionally longer yield.
- Users can wait until lock maturity while earning only day-one reward.
- Strategic users may cluster behavior around cap timing, reducing intended lock incentive.

Alternative:
- Piecewise accrual curve (e.g., linear to lock end or bounded APY schedule).

## 7. Solvency and Sustainability
Current solvency gate is local (`require(reward <= rewardPool)` on payout). Missing global safeguards:
- No proactive check that newly created stake liabilities are financeable.
- No reserve ratio target.
- No emission throttle when underfunded.

Safer pattern:
- Track `totalRewardLiability` and require `rewardPool >= bufferedLiability` at critical transitions.

## 8. Design Improvements & Hardening Opportunities in YieldCore
### Weaknesses / limitations
- Liability is implicit, not fully accounted as first-class state.
- RewardPool can be stressed by batch unlock claims.
- Penalty recycling may mask true sustainability issues.

### Alternative designs
1. **Liability-reserving stake entry**
   - Reserve max claimable reward at stake creation.
2. **Global reward index with emission schedule**
   - Move from fixed per-stake rates to system-level emissions.
3. **Dual-pool architecture**
   - Separate principal custody from reward treasury to prevent accounting ambiguity.

### Tradeoffs
- **Gas:** more state writes and updates.
- **Complexity:** more math and operational controls.
- **UX:** possibly dynamic APR instead of fixed promise.
- **Security:** materially stronger solvency guarantees.

### Real DeFi grounding
- MasterChef-style index systems and gauge-based emission models provide mature templates for deterministic reward distribution and auditable liability management.

