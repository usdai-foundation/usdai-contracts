# AGENTS.md

## Intended design

The items below are intended behavior. A report about them is not a valid finding.

- **Base yield escrow funding.** `StakedUSDai` NAV counts the accrued base yield, also when `BaseYieldEscrow` holds less because the funding is guaranteed.
- **First deposit underflow.** Before the first deposit, `convertToShares()` underflows when the deposit gives fewer than `LOCKED_SHARES` (`1e6`) shares. The deployed vaults are past their first deposit. The amount is dust and the revert loses no funds.
- **PYUSD freeze.** `USDai.isBlacklisted()` checks the local blacklist and the USDC and USDT blacklists. It does not check the PYUSD freeze list. `BLACKLIST_ADMIN_ROLE` adds PYUSD-frozen addresses to the local blacklist.
- **Lender position sent to `StakedUSDai`.** `StakedUSDai` only accepts hooks for tranches where it is the lender in the loan terms. If a lender sends its position NFT to `StakedUSDai`, `onLoanRefinanced()` reverts and that loan cannot refinance. Only the KYB'ed lender that holds the position can do this. Repayment and liquidation still work. This is self-griefing and is out of scope.
- **One tranche per loan.** `StakedUSDai` stores loans by `loanTermsHash`. The originator gives `StakedUSDai` at most one tranche in a loan. Other lenders can hold the other tranches.
- **ETH refund or bridging subsidy in `OUSDaiUtility`.** The utility can refund excess ETH or pay part of the bridge fee. This is accepted.
- **Deposit timing.** A user can time a USDai deposit around changes in the redemption share price.
- **Redemption timing.** The admin processes redemptions at a time of its choice. The outcome of a redemption depends on when borrowers repay relative to that time.
- **Optimistic share price.** The optimistic share price assumes that borrowers repay on schedule. An early or late repayment makes it too high or too low until the repayment occurs.
