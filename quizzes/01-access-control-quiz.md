# Access Control Quiz

1. What are the centralization risks of YieldCore using a single `onlyOwner` model for all privileged operations?
2. Which YieldCore owner-only functions should be timelocked, and which should remain instant for emergency response?
3. How would you map YieldCore powers into `AccessControl` roles to enforce least privilege?
4. Why is `withdrawExcessRewards` during pause a sensitive authority, and what accounting guard should be added?
5. What governance risks arise when `setLockParameters` has no bounds on daily reward and penalty rates?
6. How would a guardian/governor split improve safety relative to plain ownership?
7. Which invariant would you encode to prove no single operational role can both drain treasury-like funds and change critical parameters?
8. Propose an upgrade path from `Ownable` to role-based + timelocked governance with minimal user disruption.
