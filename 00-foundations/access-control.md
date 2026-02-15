# Access Control in YieldCore

## 1. Title
Access Control in YieldCore

## 2. Overview
YieldCore uses `Ownable` as the sole privilege model. Owner authority includes parameter setting, reward funding control, pause control, expired stake cleanup, and excess reward withdrawal. This centralization is simple but creates governance and key-management concentration risk.

## 3. Privileged Surface Mapping
Owner-only functions:
- `setLockParameters`
- `fundRewardPool`
- `cleanUpExpiredStake`
- `withdrawExcessRewards`
- `pause`
- `unpause`

User-callable state changers:
- `stake`, `claimReward`, `unstake`, `emergencyWithdraw`

Core risk: a single key controls both risk parameters and value routing under paused states.

## 4. Function-by-Function Access-Control Review (All Public Functions)
1. `setLockParameters`: Missing bounds on daily/penalty rates; owner can set punitive or absurd values.
2. `fundRewardPool`: Owner-only funding can be operational bottleneck; no multi-funder route.
3. `stake`: Open to all users as expected; no allowlist/caps for risk segmentation.
4. `calculateReward`: Public view; no access issue.
5. `claimReward`: Open; no per-user throttling or cooldown against abusive calling patterns.
6. `unstake`: Open; no optional guardian controls during incident response except global pause.
7. `cleanUpExpiredStake`: Owner can force lifecycle state transition; operationally useful but centralized.
8. `emergencyWithdraw`: User-only when paused; good user-protection path.
9. `withdrawExcessRewards`: Highly sensitive; can move protocol funds during pause with broad definition of “excess”.
10. `maxReward`: View.
11. `getStakeCount`: View.
12. `getStake`: View.
13. `getRewardsClaimed`: View.
14. `getContractBalance`: View.
15. `pause`: Owner unilateral circuit-breaker.
16. `unpause`: Owner unilateral restart.

## 5. Centralization Risk of `onlyOwner`
`onlyOwner` is straightforward, but introduces:
- **Key compromise blast radius**: immediate parameter corruption + treasury routing.
- **Governance opacity**: users cannot anticipate sudden parameter changes.
- **Censorship risk**: owner can pause indefinitely while retaining privileged operations.

## 6. Role-Based and Timelocked Alternatives
### AccessControl model
Split capabilities:
- `PARAM_ROLE`: set lock parameters (with bounds).
- `PAUSER_ROLE`: emergency pause only.
- `TREASURY_ROLE`: fund rewards.
- `SWEEP_ROLE`: limited reward sweep under strict checks.

### Timelock model
Apply delay to high-impact actions:
- Delayed: parameter changes, reward withdrawal, role admin changes.
- Immediate: pause only.

This keeps emergency response fast while making value-routing changes predictable.

## 7. Parameter Governance Risks
Current model allows instant updates of:
- Daily reward rate by lock period.
- Penalty rate by lock period.

Missing protections:
- Max/min bounds.
- Rate-of-change limits.
- Activation delay (future effective timestamp).

Safer pattern:
- Queue parameter updates with timelock and explicit “effectiveFrom” to prevent surprise user harm.

## 8. Owner Withdrawal During Pause: Risk Analysis
`withdrawExcessRewards` computes `excess = balance - rewardPool` and transfers to owner when paused. If `rewardPool` does not encode all user liabilities (e.g., principal obligations), owner could extract funds needed for redemptions.

Hardening options:
- Compute withdrawable amount against `unencumberedBalance = balance - principalLiability - reservedRewards`.
- Restrict withdrawal to governance timelock + on-chain proof checks.
- Emit detailed accounting event with liabilities snapshot.

## 9. Design Improvements & Hardening Opportunities in YieldCore
### Weaknesses / limitations
- Single-admin authority over all critical controls.
- No delayed execution for sensitive decisions.
- “Excess rewards” definition is too coarse for liability-aware custody.

### Alternative designs
1. **RBAC + Timelock hybrid**
   - Operational roles act quickly within narrow scope.
   - Strategic changes pass through timelock governance.
2. **Guardian + Governor split**
   - Guardian can pause.
   - Governor controls parameter and treasury actions with delay.
3. **Policy engine architecture**
   - Parameter updates validated by bounded policy contract.

### Tradeoffs
- **Gas/complexity:** higher deployment and runtime overhead.
- **UX:** delayed parameter activation.
- **Security:** sharply reduced single-key risk and better auditability.

### Real DeFi grounding
- Major protocols (Aave/Compound/Uniswap governance stacks) separate emergency powers from long-horizon governance and gate high-impact changes via timelocks and role segmentation.

