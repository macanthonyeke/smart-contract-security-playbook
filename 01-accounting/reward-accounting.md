# Reward Accounting

## 1. Title
Reward Accounting

## 2. Overview
Reward accounting must allocate emissions proportionally over time and stake weight without creating phantom rewards or unfair extraction opportunities.

## 3. Core Mental Model
**Definition:** Use a cumulative index (`accRewardPerShare`) and per-user checkpoint (`rewardDebt`) so entitlement is the delta between current index exposure and previously settled exposure.

Core equations:
- `pending_u = amount_u * accRPS / PRECISION - rewardDebt_u`
- After mutation: `rewardDebt_u = amount_u * accRPS / PRECISION`

### Why This Matters in DeFi/Real Protocols
Incorrect reward math silently transfers value between users and can bankrupt incentive pools long before operators detect insolvency.

## 4. Minimal Vulnerable Example (Solidity or pseudocode)
```solidity
function deposit(uint256 a) external {
    // bug: user amount changes before settling pending
    amount[msg.sender] += a;
    rewardDebt[msg.sender] = amount[msg.sender] * accRPS / 1e12;
    stake.transferFrom(msg.sender, address(this), a);
}

function claim() external {
    uint256 p = amount[msg.sender] * accRPS / 1e12 - rewardDebt[msg.sender];
    rewardDebt[msg.sender] = amount[msg.sender] * accRPS / 1e12;
    reward.transfer(msg.sender, p);
}
```

## 5. Realistic Exploit Scenario (step-by-step transaction flow)
Front-run timing race:
1. Keeper tx in mempool will call `updatePool()` and increase `accRPS`.
2. Attacker `TxA` deposits just before keeper update.
3. `TxK` executes update with new emission delta.
4. Attacker `TxB` claims immediately.
5. If ordering/checkpoint logic is wrong, attacker captures disproportionate share.

Underfunded pool sequence:
1. Protocol sets high emission schedule without funded reserve.
2. Early claimers drain reward token balance.
3. Later claims revert or underpay.
4. Pool appears healthy by accounting, but payout solvency invariant is broken.

Rounding residue numeric example:
- Epoch rewards: 10 tokens each for 3 epochs.
- Total shares each epoch = 3.
- Per epoch distribution: `10/3 = 3` each, residue `1` token.
- If residue is not carried, 3 tokens total become extractable dust.
- Attacker cycles tiny stake around epoch boundaries to capture dust-biased rounding repeatedly.

Public references:
- MasterChef-style reward distribution design discussions and known mis-implementations in yield farms.

## 6. Defensive Design Patterns
- `updatePool` first, then settle user, then mutate stake, then checkpoint debt.
- Enforce funded emissions (`distributed <= funded + reserve`).
- Carry residue forward explicitly in accumulator.
- Use high precision and tested rounding policy.
- Bound same-block claim/deposit edge behavior.

Specific off-by-one logic errors:
- Using `lastRewardBlock = block.number` before computing elapsed blocks.
- Including current block twice in elapsed interval.
- Incorrect epoch boundary comparison (`<` vs `<=`) causing one extra emission step.

## 7. EVM-Level Reasoning
- Integer division truncation is exploitable through repeated low-cost calls.
- Token transfers may deliver less than nominal amount; accounting must use balance deltas.
- Reentrancy through token hooks can desync `amount` and `rewardDebt` if not guarded.

## 8. Common Developer Mistakes
- Updating debt before paying pending rewards.
- Assuming rewards are always funded.
- Ignoring fee-on-transfer/rebasing semantics.
- Not testing boundary blocks/epochs.

## 9. Explicit, Strong Invariants
```solidity
function invariant_emissionSolvency() public {
    assertLe(totalClaimed(), totalFunded() + initialReserve());
}

function invariant_debtConsistency(address u) public {
    assertEq(rewardDebt(u), amount(u) * accRPS() / PRECISION);
}

function invariant_residueConservation() public {
    assertEq(totalDistributed() + residue(), totalAccrued());
}
```

Solidity test examples:
```solidity
function test_underfundedPool_revertsClaim() public {
    fund(1 ether); setEmission(100 ether);
    vm.expectRevert(); pool.claim();
}

function test_frontRunDepositClaimBoundary() public {
    // simulate attacker deposit before update and immediate claim
    // assert payout <= fairShare + epsilon
}
```

### How Tests Should Catch This
- Stateful fuzzing with randomized `deposit/withdraw/claim/updatePool` ordering should fail if debt consistency breaks.
- Epoch-boundary tests should assert no extra block rewards are minted.
- Adversarial tiny-stake loop should not increase attacker EV beyond configured rounding epsilon.
