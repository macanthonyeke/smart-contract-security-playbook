# Invariants

## 1. Title
Invariants

## 2. Overview
Invariants are properties that must remain true across all reachable states and transaction orderings. They are the primary mechanism for detecting latent accounting and authorization failures.

## 3. Core Mental Model
**Definition:**
- **Point-in-time invariant:** must hold at every state snapshot.
- **Temporal invariant:** must hold over transitions across blocks/epochs/time windows.

Comparison:
- Point-in-time catches immediate insolvency or unauthorized writes.
- Temporal catches schedule drift, governance delay bypass, and multi-step exploit buildup.

### Why This Matters in DeFi/Real Protocols
Many attacks are multi-transaction strategies. Unit tests may pass while temporal invariants fail over time, especially with governance and emissions.

## 4. Minimal Vulnerable Example (Solidity or pseudocode)
```solidity
function invariant_conservation() public {
    assertGe(vault.assets() + vault.collectibleDebt(), vault.liabilities());
}

function invariant_govDelay() public {
    uint256 id = gov.lastExecuted();
    if (id != 0) assertGe(gov.execTime(id), gov.queueTime(id) + MIN_DELAY);
}
```

Nested external-call invariant example:
```solidity
function invariant_noLiabilityGrowthAcrossExternalCalls() public {
    uint256 before = vault.liabilities();
    handler.callExternalAndReenter();
    uint256 afterL = vault.liabilities();
    assertLe(afterL - before, handler.maxExpectedLiabilityDelta());
}
```

## 5. Realistic Exploit Scenario (step-by-step transaction flow)
1. Oracle adapter scaling changed in upgrade.
2. Borrow module reads inflated collateral values.
3. Attackers open oversized debt positions.
4. Liquidity exits before reprice.
5. System enters bad debt despite passing local module tests.

Temporal governance sequence:
1. Proposal queued with intended 48h delay.
2. Edge-case path allows execute in same block for one selector.
3. Attacker accumulates temporary voting power and executes malicious change instantly.

Public references:
- Governance delay bypass patterns observed in multiple DAO incidents.

## 6. Defensive Design Patterns
- Property-based invariant fuzzing with adversarial handlers.
- Temporal checks for delays, emission integrals, cooldowns.
- Cross-contract normalization assertions (oracle adapter vs core consumer).
- Invariant suites before and after upgrades.

Common invariant classes and attack classes:

| Invariant | Attack Class Mitigated |
|---|---|
| Asset/liability conservation | Drain, accounting inflation |
| Authorization integrity | Privilege escalation |
| Governance delay respected | Flash governance capture |
| Oracle normalization consistency | Price manipulation / decimal bugs |
| Emission solvency | Reward pool bankruptcy |

## 7. EVM-Level Reasoning
- Invariants must survive arbitrary `CALL`/`DELEGATECALL` nesting.
- Proxy upgrades alter code while preserving storage, so invariant regressions appear post-upgrade.
- Time-based properties depend on block timestamp/number behavior at boundaries.

## 8. Common Developer Mistakes
- Testing only point-in-time assertions, not transition properties.
- Ignoring adversarial call ordering.
- Missing cross-contract invariants.
- Treating rounding mismatch as harmless without epsilon bounds.

## 9. Explicit, Strong Invariants
```solidity
function invariant_pointInTime_conservation() public {
    assertGe(assets() + collectibleDebt() - badDebt(), userLiabilities() + protocolLiabilities());
}

function invariant_temporal_emissionIntegral(uint256 t0, uint256 t1) public {
    vm.assume(t1 >= t0);
    assertEq(emittedBetween(t0, t1), integralEmissionSchedule(t0, t1));
}

function invariant_crossContract_priceConsistency() public {
    assertApproxEqAbs(core.normalizedPrice(), oracleAdapter.normalizedPrice(), 1);
}
```

### How Tests Should Catch This
- Stateful handlers should randomize caller, order, and reentrant paths; invariant failure must surface without handcrafted exploit scripts.
- Temporal tests should advance blocks/time and assert delay/emission properties over long horizons.
- Upgrade tests should run same invariant suite before and after proxy implementation changes.
