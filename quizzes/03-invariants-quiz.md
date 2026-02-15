# Invariants Quiz

1. Which solvency invariant is currently implicit in YieldCore but should be explicitly enforced in runtime checks?
2. What invariant links `ClaimedReward` event values to exact storage deltas in `rewardPool` and `rewardsClaimed`?
3. How would you encode an invariant that prevents double principal payout across `unstake` and `emergencyWithdraw` paths?
4. What parameter-bound invariants should be enforced when owner updates lock rates and penalties?
5. How can event consistency checks improve incident forensics for YieldCore lifecycle transitions?
6. Which temporal invariant should hold across pause/unpause cycles with respect to user principal safety?
7. How would you test that expired stakes never re-enter a reward-accruing state?
8. Propose a minimal set of assertion-style guards to embed directly in YieldCore functions to harden invariants at runtime.
