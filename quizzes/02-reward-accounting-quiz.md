# Reward Accounting Quiz

1. How does YieldCore’s fixed-rate-per-stake model differ from a global `accRewardPerShare` model in fairness and solvency properties?
2. Why can `MAX_REWARD_TIME = 1 day` create incentive misalignment for users choosing longer lock periods?
3. What insolvency risks remain even though `claimReward` and `unstake` check `reward <= rewardPool`?
4. How would you design a per-stake reward index system to preserve deterministic accrual while scaling to many users?
5. What liabilities should be tracked explicitly if YieldCore wants to enforce proactive funding solvency?
6. How can penalty recycling into `rewardPool` obscure true economic sustainability?
7. Which edge cases should be tested at timestamp boundaries for `calculateReward` and expiry behavior?
8. Propose a redesign that separates principal custody from reward treasury and explain how it improves accounting integrity.
