# Reward Accounting

## Overview
Reward systems fail when entitlement math is ambiguous under asynchronous deposits, withdrawals, and emissions. Correct design requires deterministic pro-rata accrual, bounded rounding error, and explicit solvency checks between promised rewards and funded reserves.

## Core Mental Model
Canonical model:
- `accRewardPerShare` (ARPS): cumulative reward index scaled by precision.
- `rewardDebt[user]`: user checkpoint equal to `user.amount * ARPS` at last mutation.
- Pending reward: `pending = user.amount * ARPS - rewardDebt[user]`.

On each state mutation:
1. Update global pool index from elapsed emissions/funding.
2. Realize user pending if needed.
3. Update user amount.
4. Reset `rewardDebt` to `user.amount * ARPS`.

This separates global accrual from user settlement and avoids O(n) loops.

## Minimal Vulnerable Example (Solidity or pseudocode)
```solidity
uint256 public accRewardPerShare; // 1e12 precision
mapping(address => uint256) public amount;
mapping(address => uint256) public rewardDebt;

function deposit(uint256 a) external {
    // Vulnerable ordering: updates user before settling pending rewards.
    amount[msg.sender] += a;
    rewardDebt[msg.sender] = amount[msg.sender] * accRewardPerShare / 1e12;
    stakeToken.transferFrom(msg.sender, address(this), a);
}

function claim() external {
    uint256 pending = amount[msg.sender] * accRewardPerShare / 1e12 - rewardDebt[msg.sender];
    rewardDebt[msg.sender] = amount[msg.sender] * accRewardPerShare / 1e12;
    rewardToken.transfer(msg.sender, pending);
}
```

## Realistic Exploit Scenario (step-by-step transaction flow)
1. Pool emits rewards per block but does not enforce funding solvency.
2. Attacker monitors mempool for keeper `updatePool()` transaction increasing ARPS materially.
3. Attacker front-runs with deposit timed just before update/claim boundary to maximize index capture.
4. Due to ordering bug, attacker’s `rewardDebt` reset suppresses fair historic debt or captures unearned delta.
5. Attacker claims immediately after update and extracts outsized rewards.
6. Underfunded pool cannot satisfy later honest claims; remaining users receive partial payouts.

Underfunded reward pool variant:
- Protocol promises fixed APY via emission schedule disconnected from reward token treasury.
- Claims succeed early, then revert/short-pay once reserve depleted.
- Attackers farm and exit early, externalizing insolvency to late participants.

Rounding residue extraction attack:
- Integer division truncation leaves residual dust each update.
- If residue handling is naive, attacker repeatedly cycles minimal stake/unstake to harvest predictable dust accumulation.
- Over many iterations, dust becomes material leakage.

## Defensive Design Patterns
- **Strict update ordering**: `updatePool` -> settle pending -> mutate stake -> set `rewardDebt`.
- **Funding-aware emissions**: cap distributed rewards by available balance or streamed funding.
- **High precision index**: use large scaler (e.g., 1e12/1e18) with bounded overflow analysis.
- **Residue policy**: track remainder explicitly and carry forward; never leave unowned truncation paths.
- **Claim throttling guards**: prevent same-block timing edge abuse when design depends on delayed settlement.
- **Separate accounting from transfer success**: only finalize state if reward transfer semantics are deterministic.

## EVM-Level Reasoning
- Arithmetic truncation is deterministic; attackers can optimize around it with many cheap calls.
- Reordering `SSTORE` around external token transfers can create inconsistent debt snapshots on reentry/revert edges.
- Fee-on-transfer/rebasing tokens alter actual received amounts versus nominal `a`; accounting must use observed deltas.
- Block timestamp/number based emissions introduce miner/validator influence at boundaries.

## Common Developer Mistakes
- Updating `rewardDebt` before paying pending rewards.
- Assuming reward token balance is always sufficient for promised emissions.
- Ignoring token behavior deviations (fee-on-transfer, rebasing, hooks).
- Using low precision scaler, causing large cumulative truncation error.
- Failing to snapshot before user amount changes.

## Explicit, Strong Invariants
- **Emission solvency**: cumulative claimed rewards <= cumulative funded rewards + initial reserves.
- **Pro-rata fairness**: user cumulative claim equals time-integral of user share of total stake (within bounded rounding epsilon).
- **Index monotonicity**: `accRewardPerShare` never decreases.
- **Debt consistency**: after each user mutation, `rewardDebt[user] == amount[user] * ARPS / PRECISION`.
- **Residue conservation**: distributed rewards + tracked residue == total accrued rewards.
