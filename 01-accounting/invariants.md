# Invariants for YieldCore

## 1. Title
Invariants for YieldCore

## 2. Overview
YieldCore security depends on value conservation between user principal, reward liabilities, and on-chain token balances. Many important invariants are implicit and should be explicitly encoded in code checks and test harnesses.

## 3. Core Invariants from YieldCore Mechanics
1. **Principal safety**: active stake principal should remain withdrawable unless emergency rules explicitly redefine it.
2. **Reward monotonicity**: `rewardsClaimed` must never decrease.
3. **Stake lifecycle consistency**: inactive stake should not later become reward-claimable.
4. **Reward pool non-negativity**: enforced by uint arithmetic and require checks.
5. **Expiry behavior**: expired stakes should not accrue or claim rewards.

## 4. Function-by-Function Invariant Review (All Public Functions)
1. `setLockParameters`: Should preserve invariant bounds (`dailyRate`, `penaltyRate` within safe limits).
2. `fundRewardPool`: Should maintain `rewardPool <= tokenBalance` post-transfer.
3. `stake`: Should preserve stake-array consistency and initialize lifecycle flags correctly.
4. `calculateReward`: Should return `0` for inactive/expired/cleanup-expired stakes.
5. `claimReward`: Must ensure `rewardPool` and `rewardsClaimed` move by equal-and-opposite deltas.
6. `unstake`: Must set `amount=0` and `active=false` exactly once and prevent double-principal payout.
7. `cleanUpExpiredStake`: Must not affect non-expired stake.
8. `emergencyWithdraw`: Must burn stake principal once and only once.
9. `withdrawExcessRewards`: Must not violate principal-plus-reserved-reward solvency.
10. `maxReward`: Should remain consistent with reward cap assumptions.
11. `getStakeCount`: Should reflect array length monotonic growth only.
12. `getStake`: View consistency.
13. `getRewardsClaimed`: View consistency.
14. `getContractBalance`: View consistency.
15. `pause`: Should not mutate accounting state beyond pause flag.
16. `unpause`: Same.

## 5. Invariants Not Explicitly Enforced in Code Today
- `stakingToken.balanceOf(this) >= totalActivePrincipal + rewardPool` (approximate solvency check).
- `penaltyByLock[lock] <= 100` and sensible bound on `dailyRateByLock[lock]`.
- `withdrawExcessRewards` should only transfer truly unencumbered funds.
- Event/value consistency: emitted principal/reward/penalty should match actual state deltas.

## 6. Assertion-Style Guards to Encode in Functions
Potential direct guards:
- In `setLockParameters`: `require(_penaltyRate <= DIVISOR)` and upper bounds for `_dailyRate`.
- In `unstake` early path: `require(penalty <= principal)` defensive clarity.
- In `withdrawExcessRewards`: compute against liabilities, not just `rewardPool`.
- In `stake`: optional pre-check that token transfer amount matches expected amount (balance delta).

## 7. Event Consistency Validation
Critical event invariants for off-chain monitoring:
- `ClaimedReward.reward` equals increment of `rewardsClaimed` and decrement of `rewardPool`.
- `UnstakeAfterLock.principal` equals pre-zeroed `s.amount`.
- `EarlyUnstake.penalty` equals amount added to `rewardPool`.
- `EmergencyWithdrawal.principal` equals user transfer amount.

Testing should parse logs and compare against storage snapshots before/after each call.

## 8. Design Improvements & Hardening Opportunities in YieldCore
### Weaknesses / limitations
- Key solvency invariants are test-only concepts, not runtime-enforced.
- Liability decomposition (principal vs rewards) is not explicit in state.
- Events are informative but not systematically checked on-chain.

### Alternative designs
1. **Explicit liability ledger**
   - Track `totalPrincipalLiability` and `totalRewardLiability`.
2. **Invariant-aware modifiers**
   - Internal post-condition checks in sensitive functions.
3. **Formalized event schema**
   - Include pre/post balances in critical events for auditability.

### Tradeoffs
- **Gas:** extra writes and checks.
- **Complexity:** more bookkeeping and potential maintenance burden.
- **Security:** stronger runtime guarantees and easier forensic analysis.

### Real DeFi grounding
- Protocols with robust risk engines increasingly encode conservative solvency constraints directly in state transition logic, not only in off-chain monitoring.

