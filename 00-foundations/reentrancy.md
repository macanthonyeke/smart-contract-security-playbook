# Reentrancy in YieldCore

## 1. Title
Reentrancy in YieldCore

## 2. Overview
YieldCore uses `ReentrancyGuard` on `claimReward`, `unstake`, `emergencyWithdraw`, and `withdrawExcessRewards`, and uses CEI-style state updates before token transfers in those paths. This blocks classic recursive drain patterns in payout functions, but security analysis must still cover cross-function behavior, multi-stake indexing, and token callback assumptions.

## 3. YieldCore Reentrancy Surfaces
Key external interaction points are all `stakingToken.safeTransfer(...)` / `safeTransferFrom(...)` operations.

- `fundRewardPool` and `stake` perform `safeTransferFrom` without `nonReentrant`.
- `claimReward`, `unstake`, `emergencyWithdraw`, and `withdrawExcessRewards` are guarded by `nonReentrant`.
- Reward computation is split into view logic (`calculateReward`) and mutating payout logic, which can create stale-read risks if future upgrades add new external calls around those reads.

### Why this matters for this contract
Even when a single function is guarded, reentrancy can still appear as:
- Cross-function entry via unguarded endpoints.
- Multi-index abuse if bookkeeping is inconsistent between stake slots.
- Token-standard edge behavior (non-standard ERC20s with callbacks/proxy hooks).

## 4. Function-by-Function Reentrancy Review (All Public Functions)
1. `setLockParameters`: No external call. Improvement: add bounds for `_dailyRate` and `_penaltyRate` to reduce governance misconfiguration risk.
2. `fundRewardPool`: External token transfer before `rewardPool += _amount`. Safer accounting alternative: use balance-delta accounting to handle fee-on-transfer tokens.
3. `stake`: External transfer before struct push; no `nonReentrant`. Usually acceptable for standard ERC20, but adding `nonReentrant` or pull-deposit batching reduces callback assumptions.
4. `calculateReward`: View-only; edge case is out-of-bounds index revert and timestamp boundary sensitivity.
5. `claimReward`: Properly guarded and updates state before transfer. Improvement: explicitly mark expired stakes in this path for consistency.
6. `unstake`: Guarded and CEI-aligned. Improvement: `require(s.active)` should likely replace `require(s.active || s.expired)` to avoid odd semantics after cleanup.
7. `cleanUpExpiredStake`: Owner-only, no transfer. Improvement: validate index via custom errors for clearer operations monitoring.
8. `emergencyWithdraw`: Guarded. Improvement: if token is fee-on-transfer, user may not receive full principal; design should document or enforce token type.
9. `withdrawExcessRewards`: Guarded. Improvement: can drain principal-backed “excess” while paused; should exclude active principal liabilities.
10. `maxReward`: View helper, but returns a simplified cap (`amount * rate / 100`) that may diverge from nuanced expectations.
11. `getStakeCount`: Safe view.
12. `getStake`: Safe view, but reverts on bad index.
13. `getRewardsClaimed`: Safe view, but reverts on bad index.
14. `getContractBalance`: Safe view.
15. `pause`: Owner-only; no delay.
16. `unpause`: Owner-only; no safety delay or checklist.

## 5. Is `nonReentrant` on `claimReward` and `unstake` sufficient?
It is sufficient for the highest-value payout paths in the current code, but not a complete strategy:

- It does not protect `stake` / `fundRewardPool` against unexpected callback behavior.
- It does not solve economic or accounting bugs; only recursive control-flow abuse.
- It assumes no future function introduces a new external call before state convergence.

Recommended hardening:
- Add explicit token allowlist assumptions (plain ERC20 only).
- Keep CEI strict in every mutating function.
- Add invariant tests that attempt callback-driven entry across all public mutators.

## 6. Multi-Stake Index Reentrancy Considerations
YieldCore stores `stakes[user]` as an array, so each index behaves like a mini-position. Reentrancy risks are lower because guarded payout functions serialize entry, but design concerns remain:

- A malicious token callback could try to call a different index (`_index + 1`) in the same tx; `nonReentrant` blocks this today.
- If future logic introduces index-moving operations (compaction, merge), stale index references can become a new exploit class.

Safer scalable alternative:
- Use stake IDs (`mapping(uint256 => StakeInfo)` + owner mapping) instead of array index coupling.

## 7. Pull vs Push Reward Distribution
Current model is push-on-claim (`safeTransfer` in same call).

- **Push pros:** simple UX; immediate settlement.
- **Push cons:** external call in core logic; harder to isolate transfer failures.
- **Pull alternative:** record claimable credits and let users withdraw separately.

Tradeoff summary:
- Pull-based architecture improves isolation and composability, but adds state and one extra user action.

## 8. Design Improvements & Hardening Opportunities in YieldCore
### Weaknesses / limitations
- Reentrancy defense is function-local, not architecture-level.
- `safeTransferFrom` paths (`stake`, `fundRewardPool`) rely on token behavior assumptions.
- Array-index stake model can become fragile under future feature growth.

### Alternative designs
1. **Two-phase accounting + payout queue**
   - Phase A: settle reward/unstake into internal credit.
   - Phase B: dedicated `withdrawCredit` transfer path.
2. **Stake NFT model**
   - Each stake represented by transferable/non-transferable position token with isolated accounting.
3. **Modular vault split**
   - Core accounting module has zero token transfers; treasury module handles transfers only.

### Tradeoffs
- **Gas:** extra writes for credit-based settlement.
- **Complexity:** more modules and user actions.
- **UX:** delayed token receipt unless batched.
- **Security:** much stronger fault isolation and clearer invariants.

### Real DeFi grounding
- MasterChef-like systems often separate reward accrual and token extraction checkpoints.
- Mature lending protocols isolate accounting from token transfer orchestration and rely on explicit invariant testing across modules.

