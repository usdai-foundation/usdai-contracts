* StakedUSDai v1.10 - 07/08/2026
    * Remove migration logic for LoanRouter v1.
    * Add support for LoanRouterV2 `onLoanRefinanced()` hook.

* StakedUSDai v1.9 - 06/24/2026
    * Migrate from LoanRouter to LoanRouterV2.
    * Add support for EscrowTimelock.
    * Temporarily remove support for DepositTimelock.

* OToken v1.1 - 04/24/2026
    * Replace `BRIDGE_ADMIN_ROLE` with immutable address.
    * Add `pause()` and `unpause()` APIs.

* USDai v1.5 - 04/24/2026
    * Remove completed `convertBaseToken()` function.
    * Remove supply cap.
    * Replace `BRIDGE_ADMIN_ROLE` with immutable address.
    * Add `pause()` and `unpause()` APIs.
    * Fix visibility of internal scale helper functions.
    * Add missing interfaces to `supportsInterface()` API.

* StakedUSDai v1.8 - 04/24/2026
    * Remove completed `migrate()` function.
    * Remove legacy base token APIs.
    * Replace `BRIDGE_ADMIN_ROLE` with immutable address.

* OUSDaiUtility v1.7 - 01/23/2026
    * Add blacklist support with refund mechanism.

* StakedUSDai v1.7 - 01/23/2026
    * Remove deprecated `PoolPositionManager`.
    * Add timelock refund handling to `LoanRouterPositionManager`.
    * Migrate blacklist to use USDai state.
    * Add support for new base token in USDai.
    * Add `withdrawAdminFee()` API to `LoanRouterPositionManager`.
    * Add `repaymentBalances()` getter to `LoanRouterPositionManager`.

* USDai v1.4 - 01/23/2026
    * Migrate base token to PYUSD.
    * Add blacklist support.

* BaseYieldEscrow v1.0 - 01/23/2026
    * Initial release.

* ChainlinkPriceOracle v1.1 - 01/23/2026
    * Migrate to PYUSD price feed.

* StakedUSDai v1.6 - 12/12/2025
    * Add temporary `poolGarbageCollect()` API to `PoolPositionManager` to
      clean up deprecated pools state.

* StakedUSDai v1.5 - 12/05/2025
    * Remove completed `migrate()` function.
    * Add `LoanRouterPositionManager`.
    * Change individual redemption timelocks to fixed redemption windows.

* OUSDaiUtility v1.6 - 12/05/2025
    * Add `whitelistedOAdapters()` getter.

* StakedUSDai v1.4 - 12/05/2025
    * Deprecate `PoolPositionManager`.
    * Add USDai deposit state.

* OUSDaiUtility v1.5 - 09/26/2025
    * Add support for stake action.

* PredepositVault v1.0 - 09/22/2025
    * Initial release.

* StakedUSDai v1.3 - 09/22/2025
    * Add `bridgedSupply()` getter.

* USDai v1.3 - 09/22/2025
    * Remove completed `migrate()` function.
    * Fix parameter name in `Withdrawn` event.

* OUSDaiUtility v1.4 - 09/22/2025
    * Propagate source eid to USDaiQueuedDepositor for queued deposits.

* USDaiQueuedDepositor v1.3 - 09/22/2025
    * Add deposit eid whitelist.
    * Add support for swap aggregators to `service()`.

* USDai v1.2 - 09/04/2025
    * Add support for deposit admin role that can bypass supply cap.

* USDai v1.1 - 08/29/2025
    * Add support for supply cap.

* USDaiQueuedDepositor v1.2 - 08/21/2025
    * Migrate to servicing queue count instead of amount in `service()`.

* USDaiQueuedDepositor v1.1 - 08/16/2025
    * Add support for deposit cap.

* OUSDaiUtility v1.3 - 08/15/2025
    * Add support for local chain send, deposit, deposit and stake, and queued
      deposit.

* USDaiQueuedDepositor v1.0 - 08/15/2025
    * Initial release.

* StakedUSDai v1.2 - 07/31/2025
    * Net out admin fee in NAV calculation.

* StakedUSDai v1.1 - 06/25/2025
    * Add admin fee support.

* OUSDaiUtility v1.2 - 06/19/2025
    * Add destination eid and recipient parameters to ComposerDeposit and
      ComposerDepositAndStake events.

* OUSDaiUtility v1.1 - 06/18/2025
    * Add native fee refund in case of revert.

* OUSDaiUtility v1.0 - 05/28/2025
    * Initial release.

* StakedUSDai v1.0 - 05/13/2025
    * Initial release.

* USDai v1.0 - 05/13/2025
    * Initial release.
