# Reentrancy Quiz

1. In YieldCore, why does using `nonReentrant` on `claimReward` and `unstake` reduce but not eliminate all reentrancy risk?
2. What additional risk assumptions are introduced by leaving `stake` and `fundRewardPool` without `nonReentrant`?
3. How could a malicious token callback attempt cross-function reentrancy across different stake indices, and what currently blocks it?
4. What design advantages and drawbacks come from moving YieldCore to a pull-based credit withdrawal model instead of direct push transfers?
5. Which storage updates in `unstake` are critical to preserve CEI ordering, and what could happen if transfer were moved earlier?
6. How would you redesign stake identification to reduce future index-coupling risk in multi-position reentrancy scenarios?
7. What invariant-based test would you write to prove no double-payout can occur across nested calls?
8. If YieldCore were upgraded with new token integrations, what reentrancy hardening checklist should be mandatory before deployment?
