# Access Control

## Overview
Access control failures are usually value-routing failures: unauthorized principals gain write access to parameters, balances, upgrade paths, or emergency controls. Most critical incidents are not missing `onlyOwner`; they are flawed privilege boundaries and unsafe role composition.

## Core Mental Model
Define a privilege graph: principals -> capabilities -> affected invariants. Security review checks whether any path grants a principal the ability to violate conservation, authorization, or upgrade integrity constraints. Every privileged action should have explicit blast-radius bounds and delay/oversight assumptions.

## Minimal Vulnerable Example (Solidity or pseudocode)
```solidity
contract Vault {
    address public owner;
    mapping(address => bool) public isOperator;
    address public implementation;

    function setOperator(address who, bool ok) external {
        require(msg.sender == owner || isOperator[msg.sender], "forbidden");
        // Privilege escalation: operators can add operators.
        isOperator[who] = ok;
    }

    function upgradeTo(address newImpl) external {
        require(isOperator[msg.sender], "forbidden");
        implementation = newImpl;
    }
}
```

## Realistic Exploit Scenario (step-by-step transaction flow)
1. Protocol designates automation bot as low-trust operator for routine tasks.
2. Buggy role logic allows any operator to grant operator role to arbitrary addresses.
3. Attacker compromises bot key or obtains temporary operator privileges.
4. Attacker self-grants persistent operator/admin powers.
5. Attacker calls privileged parameter setters: fee recipient, oracle source, liquidation bonus.
6. Attacker invokes upgrade function to malicious implementation and drains assets.
7. Governance cannot react in time because no timelock or pause separation existed.

## Defensive Design Patterns
- **Least privilege by capability**: split roles by narrow action set (pause, parameter-tune, treasury-move, upgrade).
- **No self-escalation**: role admins should be disjoint from role members for sensitive roles.
- **Timelocked governance**: high-impact actions delayed with cancel path and monitoring window.
- **Two-step ownership transfer**: `transferOwnership` + `acceptOwnership` to prevent misassignment.
- **Multisig + quorum diversity**: avoid single-key catastrophic authority.
- **Explicit upgrade gatekeeping**: `onlyProxyAdmin`, immutable admin routing, and event-rich upgrade pipeline.

Upgradeable proxy risk hotspots:
- **Uninitialized implementation/proxy**: attacker initializes and captures admin state.
- **Storage collision**: new implementation corrupts admin or accounting slots due to layout mismatch.
- **Exposed upgrade function**: implementation contains callable upgrade entrypoints not properly restricted.

Governance and parameter manipulation risks:
- Setting oracle heartbeat too long, allowing stale price usage.
- Raising borrow caps/LTV abruptly to create bad debt window.
- Changing fee routing to attacker-controlled sink.
- Lowering liquidation penalties to enable self-liquidation extraction.

## EVM-Level Reasoning
- Authorization is runtime predicate evaluation on `msg.sender` and storage roles; delegatecall-based proxies execute implementation code in proxy storage context.
- Any storage slot overlap in upgradeable systems can mutate authorization variables unintentionally.
- Constructor logic is absent in proxy deployments; initialization must be explicit and one-time guarded.
- `delegatecall` turns implementation bugs into proxy-state compromise, including role mappings and admin addresses.

## Common Developer Mistakes
- Reusing `DEFAULT_ADMIN_ROLE` as operational role.
- Allowing role members to administer their own role.
- Failing to revoke deployer/bootstrap privileges.
- Missing timelock on upgrade and treasury functions.
- Using `tx.origin` or brittle EOA checks for auth.
- Forgetting initializer guards (`initializer`/versioned reinitializer).

## Explicit, Strong Invariants
- **Authorization invariant**: for each privileged function `f`, only principals in approved capability set `C_f` can change protected state.
- **Non-escalation invariant**: no principal outside governance root can grant itself or peers a role with wider capability than currently held.
- **Upgrade integrity invariant**: implementation changes require timelock + authorized executor and preserve storage layout constraints.
- **Parameter safety invariant**: governance-tunable parameters remain inside audited min/max bounds.
- **Least-privilege invariant**: compromise of any single operational key cannot transfer custody or upgrade logic.
