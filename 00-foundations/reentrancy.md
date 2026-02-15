# Reentrancy

## 1. Title
Reentrancy

## 2. Overview
Reentrancy is a control-flow attack where untrusted external code re-enters protocol logic before the original function completes, allowing repeated use of stale assumptions.

## 3. Core Mental Model
**Definition:** A state transition is reentrant-vulnerable when external control transfer occurs before all critical state writes that enforce value conservation and authorization.

Think in three layers:
1. **Precondition snapshot** (what checks depend on).
2. **State transition** (what must become true atomically).
3. **External interaction boundary** (where attacker can interrupt).

If layer (3) happens before layer (2) is finalized, invariants can be violated under nested call graphs.

Reentrancy taxonomy:
- Single-function reentrancy.
- Cross-function reentrancy.
- Cross-contract reentrancy.
- Read-only reentrancy.
- Token-hook reentrancy (ERC777/1155).

### Why This Matters in DeFi/Real Protocols
Lending, vaults, and AMMs rely on globally consistent balances, debt shares, and price snapshots. Reentrancy breaks this consistency and can turn small local bugs into system-wide insolvency.

## 4. Minimal Vulnerable Example (Solidity or pseudocode)
```solidity
contract Vault {
    mapping(address => uint256) public bal;

    function deposit() external payable {
        bal[msg.sender] += msg.value;
    }

    function withdraw(uint256 amount) external {
        require(bal[msg.sender] >= amount, "insufficient");
        (bool ok,) = msg.sender.call{value: amount}(""); // interaction first
        require(ok, "send failed");
        bal[msg.sender] -= amount; // effect too late
    }
}
```

ERC777 hook-shaped vulnerability:
```solidity
function deposit777(uint256 amount) external {
    shares[msg.sender] += previewShares(amount); // credited early
    rewardDebt[msg.sender] = shares[msg.sender] * accRewardPerShare / 1e12;
    token777.send(address(this), amount, ""); // may trigger tokensReceived callback
    totalAssets += amount;
}
```

## 5. Realistic Exploit Scenario (step-by-step transaction flow)
Transaction sequence (single-function):
1. `Tx1`: attacker deposits 10 ETH. State: `bal[A]=10`, `vaultETH=10`.
2. `Tx2`: attacker calls `withdraw(10)`.
3. Vault performs external `call` before decrement; fallback re-enters `withdraw(10)`.
4. Nested frame still sees `bal[A]=10`; sends another 10 ETH.
5. Outer frame resumes and decrements once. Final: `bal[A]=0`, `vaultETH=-10` effective loss.

Transaction sequence (read-only reentrancy):
1. Protocol computes collateral factor using `view` getter from a vault during liquidation.
2. Getter depends on transient state updated after an external oracle adapter call.
3. Adapter callback re-enters and changes reserve ratio path.
4. Liquidation engine reads temporarily inflated health factor and skips liquidation.
5. Attacker exits with bad debt window opened; no direct state mutation in the read path was needed.

Public references:
- The DAO (2016) classic recursive withdraw.
- Curve read-only reentrancy incident class (2022) illustrating pricing/`view` path hazards.

## 6. Defensive Design Patterns
- CEI: checks -> effects -> interactions.
- Mutex (`ReentrancyGuard`) on critical entry points.
- Pull-payment for user withdrawals/claims.
- Snapshot-and-settle design (freeze inputs before external calls).
- Explicit non-reentrant read paths where views feed critical decisions.

| Pattern | Best Use | Limitation | Strong Pairing |
|---|---|---|---|
| CEI | Simple single-function flows | Misses cross-function/read-only paths | CEI + invariant tests |
| Mutex | Shared mutable state | Can block composability | mutex + segmented state |
| Pull payments | Payout-heavy systems | Requires user claim UX | pull + claim caps |
| Snapshot checks | Oracle/health reads | Snapshot freshness risk | snapshot + staleness bounds |

## 7. EVM-Level Reasoning
- `CALL` transfers control and gas; attacker can invoke any reachable external/public entrypoint.
- `SSTORE` ordering defines which values reentrant frames observe.
- `DELEGATECALL` extends reentrancy risk across proxy modules using shared storage.
- ERC777 and ERC1155 receiver hooks are explicit callback edges.

Compiler/EVM version notes:
- Solidity 0.8+ adds checked arithmetic but does not prevent reentrancy.
- Gas-cost changes across forks (e.g., stipend assumptions) invalidate reliance on `transfer` as a guard.
- Newer compiler defaults (ABI encoder v2, optimizer behavior) can change call surface but not the core reentry model.

## 8. Common Developer Mistakes
- Assuming `view` paths are always safe when used by critical execution logic.
- Guarding `withdraw` but not sibling state-mutating functions.
- Updating user state but forgetting global state before interaction.
- Trusting token transfer semantics across ERC20/777/1155 uniformly.

## 9. Explicit, Strong Invariants
```solidity
function invariant_globalSolvency() public {
    assertGe(totalAssetsOnChain() + collectibleDebt(), totalUserClaims());
}

function invariant_singleUseEntitlement(address u) public {
    assertLe(claimed[u][epoch], entitled[u][epoch]);
}

function invariant_indexMonotonic() public {
    assertGe(accRewardPerShare(), lastAccRewardPerShare());
}
```

### How Tests Should Catch This
- Fuzz with attacker callback contract that re-enters all public functions.
- Invariant harness should fail when nested calls make `totalUserClaims()` exceed assets.
- Add a test where liquidation reads a view during reentrant callback and assert liquidation eligibility is unchanged.
