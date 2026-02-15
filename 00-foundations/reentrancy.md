# Reentrancy

## Overview
Reentrancy occurs when control flow leaves a contract before its critical state transitions are finalized, then re-enters and observes or mutates partially updated state. The result is duplicated entitlement, broken accounting, and insolvency. Treat every external call as an adversarial context switch.

## Core Mental Model
Model each state-changing function as an atomic transition over a ledger invariant set. Reentrancy is a violation of atomicity: an attacker forces interleaving of transitions so that preconditions are checked against stale state and effects are applied multiple times. The defense objective is not only “block recursive calls,” but “preserve invariant truth under arbitrary call interleavings.”

Taxonomy:
- **Single-function reentrancy**: re-enter the same function before state update (classic withdraw bug).
- **Cross-function reentrancy**: enter another function sharing mutable state (e.g., `withdraw()` then `transferStake()`).
- **Cross-contract reentrancy**: re-entry path traverses another protocol that calls back.
- **Read-only reentrancy**: view/read path returns manipulated transient state used by downstream pricing/health checks.
- **Token-hook reentrancy**: callbacks from token standards (ERC777 `tokensReceived`, ERC1155 receiver hooks) re-enter business logic.

## Minimal Vulnerable Example (Solidity or pseudocode)
```solidity
// Vulnerable: interaction before effect.
function withdraw(uint256 amount) external {
    require(balance[msg.sender] >= amount, "insufficient");
    (bool ok,) = msg.sender.call{value: amount}("");
    require(ok, "send failed");
    balance[msg.sender] -= amount;
}
```

ERC777 callback-shaped variant:
```solidity
// Vault accepts ERC777 and credits shares before finalizing global accounting.
function deposit(uint256 amount) external {
    shares[msg.sender] += quoteShares(amount);
    // ERC777 transfer can trigger recipient/sender hooks and re-enter claim/withdraw.
    token.send(address(this), amount, "");
    totalAssets += amount;
}
```

## Realistic Exploit Scenario (step-by-step transaction flow)
1. Attacker deploys a contract with fallback/`tokensReceived` callback.
2. Attacker seeds a small position in vulnerable vault.
3. Attacker calls `withdraw()` (or `deposit()` in ERC777-hook scenario).
4. Vault performs external call (`call`, token transfer/hook trigger) before finalizing ledger state.
5. Callback re-enters `withdraw()`/`claim()` while original frame still sees old balances or old cumulative index.
6. Re-entry drains additional funds or mints excess entitlement.
7. Loop repeats until vault balance or gas limits are reached.

DAO technical breakdown:
- The DAO split mechanism transferred ETH before decrementing sender balance.
- Attacker contract fallback re-entered split/withdraw path repeatedly.
- Each recursion passed balance checks against stale state.
- Net effect: same entitlement consumed multiple times, draining funds into child DAO structure.
- Root cause: violated atomicity and invariant “sum(user balances) <= treasury assets.”

## Defensive Design Patterns
- **CEI (Checks-Effects-Interactions)**: apply all effects before external interaction.
- **ReentrancyGuard/mutex**: serialize entry to critical sections (`nonReentrant`) when state coupling is broad.
- **Pull payments**: store owed amounts and let users withdraw in isolated transfer function with hardened logic.
- **State partitioning**: isolate accounting by function or subsystem to reduce shared mutable state.
- **External-call minimization**: avoid callbacks during critical state transitions; wrap token operations defensively.
- **Two-phase accounting**: commit debt/credit, then settle transfer separately.

CEI limitations:
- CEI in one function does not protect cross-function paths sharing state.
- CEI does not solve read-only reentrancy if external observers consume transient values.
- CEI fails if invariants depend on external contracts with mutable callbacks.
- CEI is brittle in upgradeable systems where new functions can introduce unsafe interaction order.

## EVM-Level Reasoning
- `CALL` hands control to untrusted code with forwarded gas; any reachable public/external function can be invoked.
- Storage writes (`SSTORE`) only become visible in current execution context immediately; if delayed until after `CALL`, re-entrant frames read stale slots.
- Reverts roll back frame-local effects but do not guarantee protocol-level safety if partial operations are split across multiple external calls.
- Token hooks (ERC777/1155) are explicit callback points; treat them as attacker-controlled re-entry edges in call graph analysis.

## Common Developer Mistakes
- Assuming `transfer`/2300 stipend is a permanent mitigation.
- Guarding only one function while other state-mutating functions remain re-enterable.
- Updating user balance but not global totals (or vice versa) before interaction.
- Trusting ERC20 semantics while integrating ERC777-like tokens with hooks.
- Ignoring read-only reentrancy in pricing, health-factor, or collateral checks.

## Explicit, Strong Invariants
- **Global solvency**: `totalAssetsOnChain + collectibleDebt >= sum(userWithdrawable)` at all times.
- **Single-consumption entitlement**: for each user and epoch/index, claimable rewards can be reduced from positive to zero at most once per entitlement unit.
- **Conservation under interleaving**: any prefix of nested call frames must not observe `sum(userBalances) > accountedAssets`.
- **Monotonic cumulative index**: reward/share indices never decrease and user settlement cannot exceed delta-index entitlement.
- **Authorization + liveness boundary**: only intended principals can trigger settlement on behalf of a user; failed transfer paths must not mint or burn net value.
