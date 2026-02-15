# Invariants

## Overview
Invariants are non-negotiable truths that must hold across every reachable state, including adversarial sequencing, reentrancy, oracle shocks, and governance actions. Useful invariants are machine-checkable properties tied directly to value conservation and authorization boundaries.

## Core Mental Model
Define invariants by domain and enforce them continuously:
- **Conservation**: value is neither created nor destroyed except via explicit, bounded mechanisms.
- **Authorization**: only approved principals can trigger privileged transitions.
- **Temporal**: time-delayed logic respects minimum delays and emission schedules.
- **Cross-contract**: integrated components remain consistent at boundaries.

Write each invariant as a property over state variables and event-driven transitions; then fuzz transaction ordering and caller identities.

## Minimal Vulnerable Example (Solidity or pseudocode)
```solidity
// Pseudocode invariant harness idea (Foundry style)
function invariant_totalAssetsCoverLiabilities() public {
    assert(vault.totalAssets() + vault.outstandingDebt() >= vault.totalLiabilities());
}

function invariant_onlyGovCanUpgrade() public {
    // track last upgrader in handler
    assert(handler.lastUnauthorizedUpgradeAttemptFailed());
}
```

## Realistic Exploit Scenario (step-by-step transaction flow)
1. Protocol has individually audited modules but no cross-contract invariant tests.
2. New release changes oracle adapter decimals.
3. Lending market health checks consume mis-scaled price; borrowers appear overcollateralized.
4. Attackers borrow against inflated collateral and withdraw liquidity.
5. Local unit tests pass; system fails because invariant “borrow value <= collateral value * LTV” across contracts was never encoded.

Temporal failure example:
1. Governance queue delay intended to be 48h.
2. Misconfigured timelock allows same-block execution for specific function selector.
3. Attacker with temporary voting majority enacts malicious parameter and executes immediately.

## Defensive Design Patterns
- **Property-based testing (Foundry invariants)**: randomized call sequences with adversarial handlers.
- **Stateful fuzzing**: model attacker actors, privileged actors, and market actors concurrently.
- **Temporal assertions**: encode minimum delay between proposal queue and execution; enforce emission-rate continuity.
- **Cross-contract snapshots**: assert adapter-normalized values match core contract assumptions.
- **Bounded-math assertions**: verify rounding error stays within fixed epsilon envelope.

Foundry-style examples:
```solidity
function invariant_conservation() public {
    uint256 lhs = token.balanceOf(address(vault)) + vault.totalOutstandingLoans();
    uint256 rhs = vault.totalDeposits() + vault.protocolFeesAccrued();
    assertGe(lhs, rhs);
}

function invariant_timelockDelayRespected() public {
    if (gov.lastExecutedProposalId() != 0) {
        assertGe(gov.executionTime(gov.lastExecutedProposalId()),
                 gov.queuedTime(gov.lastExecutedProposalId()) + MIN_DELAY);
    }
}
```

## EVM-Level Reasoning
- Invariants must hold under arbitrary call ordering and nested `CALL`/`DELEGATECALL` contexts.
- Proxy upgrades modify behavior without changing storage; invariant suites must run across upgrade boundaries.
- Timestamp-based logic is only approximately monotonic and validator-influenced within protocol limits.
- External token semantics can violate naive assumptions (`balanceOf` changes outside direct transfers).

## Common Developer Mistakes
- Writing post-condition checks only for happy-path unit tests.
- Asserting exact equality where truncation/rebasing requires epsilon bounds.
- Ignoring authorization invariants in test handlers (all calls from privileged actor).
- Not testing after upgrades or parameter changes.
- Omitting cross-contract invariants between vault/oracle/controller.

## Explicit, Strong Invariants
- **Conservation invariant**: `assets + collectibleDebt - badDebt >= userLiabilities + protocolLiabilities`.
- **Authorization invariant**: unauthorized callers cannot mutate privileged storage or execute upgrades.
- **Temporal emission invariant**: cumulative emitted rewards over `[t0,t1]` equals configured emission function integral, capped by funding.
- **Governance delay invariant**: every executed proposal satisfies `executionTime >= queueTime + minDelay`.
- **Cross-contract price consistency invariant**: normalized oracle price consumed by core logic equals adapter-reported price within precision bounds.
