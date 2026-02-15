# Access Control

## 1. Title
Access Control

## 2. Overview
Access control defines who can change critical state. In DeFi, authorization bugs are usually value-routing bugs: unauthorized actors gain power to mint, upgrade, drain, or censor.

## 3. Core Mental Model
**Definition:** Access control is the mapping from principals to capabilities, with constraints on delegation, escalation, and timing.

Model a privilege graph:
- Nodes: EOAs, multisigs, timelocks, modules.
- Edges: grant/revoke/execute rights.
- Protected invariants: custody, upgrade integrity, parameter safety.

### Role inheritance anti-patterns
- Child role inherits admin rights unintentionally from parent role.
- `DEFAULT_ADMIN_ROLE` reused as day-to-day operator.
- Role can grant itself a stronger role through indirect admin chain.

### Why This Matters in DeFi/Real Protocols
Most catastrophic losses come from privileged functions (upgrade, oracle, treasury) being reachable by the wrong actor or reachable too quickly.

## 4. Minimal Vulnerable Example (Solidity or pseudocode)
```solidity
contract ACL {
    mapping(bytes32 => mapping(address => bool)) public hasRole;
    bytes32 constant OPERATOR = keccak256("OPERATOR");
    bytes32 constant ADMIN = keccak256("ADMIN");

    function grant(bytes32 role, address who) external {
        require(hasRole[role][msg.sender], "self-admin anti-pattern");
        hasRole[role][who] = true; // operator can create more operators forever
    }

    function upgradeTo(address impl) external {
        require(hasRole[OPERATOR][msg.sender], "forbidden"); // over-broad
        _setImplementation(impl);
    }
}
```

Proxy storage collision snippet:
```solidity
// Proxy slot 0 stores admin.
contract ProxyStorage { address public admin; }

// New impl mistakenly puts uint256 totalSupply at slot 0.
contract ImplV2 {
    uint256 public totalSupply; // collides with admin slot in proxy context
    function mint(uint256 x) external { totalSupply += x; }
}
```
If called via proxy/delegatecall, `mint` mutates slot 0 and corrupts admin, potentially breaking or hijacking access control.

## 5. Realistic Exploit Scenario (step-by-step transaction flow)
Sequence (privilege escalation + upgrade):
1. `Tx1`: bot key has OPERATOR for routine pausing.
2. `Tx2`: attacker compromises bot and calls `grant(OPERATOR, attacker)`.
3. `Tx3`: attacker sets malicious implementation via `upgradeTo`.
4. `Tx4`: malicious logic drains treasury.

Sequence (governance delay + hierarchy accumulation):
1. Proposal A grants ROLE_X as temporary emergency role.
2. Proposal B queued to change ROLE_X admin to itself after delay.
3. Due to hierarchy misdesign, ROLE_X can then grant ADMIN-like capabilities.
4. After delay, attacker-controlled ROLE_X accumulates privileges not intended at proposal time.

Public references:
- Parity multisig library authorization failure class (2017).
- Multiple proxy-admin misconfiguration incidents across upgradeable protocols.

## 6. Defensive Design Patterns
- Capability-scoped roles (separate pause, parameter, treasury, upgrade).
- Non-self-admin role graph (`roleAdmin[role] != role` for critical roles).
- Timelock for high-impact ops, fast-path pause only.
- Two-step ownership handover.
- Upgrade allowlist + on-chain bytecode hash checks.
- Storage layout checks in CI for proxy upgrades.

Invariant-tied pattern tests:
```solidity
function invariant_onlyUpgradeRoleCanUpgrade(address caller) public {
    vm.prank(caller);
    if (!hasRole(UPGRADER, caller)) vm.expectRevert();
    try proxy.upgradeTo(address(newImpl)) {} catch {}
}

function invariant_noSelfEscalation(address a) public {
    assertFalse(canEscalateWithoutTimelock(a));
}
```

## 7. EVM-Level Reasoning
- Authorization checks execute in proxy storage context under `delegatecall`.
- Storage collisions can rewrite role/admin slots.
- Uninitialized proxy/implementation allows hostile initializer capture.
- Selector clashes and fallback routing can expose unintended privileged paths.

## 8. Common Developer Mistakes
- Leaving initialization callable after deployment.
- Making operational role admin of itself.
- No bound checks on governance-set parameters.
- Forgetting revoke flows for bootstrap keys.

## 9. Explicit, Strong Invariants
```solidity
function invariant_authz(address c) public {
    if (!hasRole(PARAM_ADMIN, c)) assertEq(lastParamSetter(), trustedParamSetter());
}

function invariant_upgradeIntegrity() public {
    assertTrue(lastUpgradeExecutedByTimelock());
    assertTrue(storageLayoutCompatible(currentImpl()));
}

function invariant_leastPrivilege() public {
    assertFalse(singleOperationalKeyCanMoveTreasuryAndUpgrade());
}
```

### How Tests Should Catch This
- Differential tests across upgrade simulate storage layout drift; fail if admin slot changes unexpectedly.
- Fuzz role grant/revoke sequences; fail if unprivileged caller can eventually upgrade.
- Temporal test: queue proposal then attempt early execute; must revert before `minDelay`.
