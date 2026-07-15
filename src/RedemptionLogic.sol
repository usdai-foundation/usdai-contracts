// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./StakedUSDaiStorage.sol";

import "./interfaces/IStakedUSDai.sol";

/**
 * @title Redemption Logic
 * @author USD.AI Foundation
 */
library RedemptionLogic {
    using EnumerableSet for EnumerableSet.UintSet;

    /*------------------------------------------------------------------------*/
    /* Constants */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Fixed point scale
     */
    uint256 internal constant FIXED_POINT_SCALE = 1e18;

    /**
     * @notice Maximum redemption queue scan count
     */
    uint256 internal constant MAX_REDEMPTION_QUEUE_SCAN_COUNT = 150;

    /**
     * @notice Max active redemptions per controller
     */
    uint256 internal constant MAX_ACTIVE_REDEMPTIONS_COUNT = 50;

    /**
     * @notice Minimum redemption shares
     */
    uint256 internal constant MIN_REDEMPTION_SHARES = 1e18;

    /**
     * @notice Redemption window
     */
    uint64 internal constant REDEMPTION_WINDOW = 30 days;

    /*------------------------------------------------------------------------*/
    /* Getters */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Get redemption and shares ahead
     * @param redemptionState_ Redemption state
     * @param redemptionId Redemption ID
     * @return Redemption, shares ahead
     */
    function _redemption(
        StakedUSDaiStorage.RedemptionState storage redemptionState_,
        uint256 redemptionId
    ) external view returns (IStakedUSDai.Redemption memory, uint256) {
        /* Look up redemption */
        IStakedUSDai.Redemption memory redemption_ = redemptionState_.redemptions[redemptionId];

        /* Get shares ahead */
        uint256 sharesAhead;
        uint256 count;
        uint256 prevRedemptionId = redemption_.prev;
        while (prevRedemptionId != 0 && count < MAX_REDEMPTION_QUEUE_SCAN_COUNT) {
            /* Get redemption */
            IStakedUSDai.Redemption memory prevRedemption = redemptionState_.redemptions[prevRedemptionId];

            /* If previous redemption pending is 0, break */
            if (prevRedemption.pendingShares == 0) break;

            /* Add pending shares */
            sharesAhead += prevRedemption.pendingShares;

            /* Get previous redemption */
            prevRedemptionId = prevRedemption.prev;

            /* Increment count */
            count++;
        }

        return (redemption_, sharesAhead);
    }

    /**
     * @notice Get available redemption amount and shares
     * @param redemptionState_ Redemption state
     * @param controller Controller address
     * @return Amount, shares
     */
    function _redemptionAvailable(
        StakedUSDaiStorage.RedemptionState storage redemptionState_,
        address controller
    ) external view returns (uint256, uint256) {
        uint256 amount;
        uint256 shares;

        /* Get redemption IDs */
        uint256[] memory redemptionIds = redemptionState_.redemptionIds[controller].values();

        /* Iterate through redemption IDs */
        for (uint256 i; i < redemptionIds.length; i++) {
            /* Look up redemption */
            IStakedUSDai.Redemption memory redemption_ = redemptionState_.redemptions[redemptionIds[i]];

            /* Add withdrawable amount and redeemable shares which are already serviced */
            amount += redemption_.withdrawableAmount;
            shares += redemption_.redeemableShares;
        }

        /* Return amount and shares */
        return (amount, shares);
    }

    /**
     * @notice Get redemption shares ready
     * @param redemptionState_ Redemption state
     * @return Redemption shares ready
     */
    function _redemptionSharesReady(
        StakedUSDaiStorage.RedemptionState storage redemptionState_
    ) external view returns (uint256) {
        /* Get head redemption ID */
        uint256 head = redemptionState_.head;

        /* Scan redemptions */
        uint256 shares;
        while (head != 0) {
            /* Get redemption */
            IStakedUSDai.Redemption memory redemption_ = redemptionState_.redemptions[head];

            /* Stop if redemption timestamp is past redemption window */
            if (redemption_.redemptionTimestamp >= block.timestamp) break;

            /* Add pending shares */
            shares += redemption_.pendingShares;

            /* Update head */
            head = redemption_.next;
        }

        return shares;
    }

    /*------------------------------------------------------------------------*/
    /* Helpers */
    /*------------------------------------------------------------------------*/

    /**
     * @notice Compute next redemption timestamp
     * @param genesisTimestamp Genesis timestamp
     * @return Next redemption timestamp
     */
    function _nextRedemptionTimestamp(
        uint64 genesisTimestamp
    ) internal view returns (uint64) {
        /* Compute count */
        uint64 count = block.timestamp >= genesisTimestamp
            ? uint64((block.timestamp - genesisTimestamp) / REDEMPTION_WINDOW + 1)
            : 0;

        /* Return next redemption timestamp */
        return genesisTimestamp + count * REDEMPTION_WINDOW;
    }

    /**
     * @notice Withdraw assets
     * @param redemptionState_ Redemption state
     * @param amount Amount to withdraw
     * @param controller Controller address
     * @return Shares redeemed
     */
    function _withdraw(
        StakedUSDaiStorage.RedemptionState storage redemptionState_,
        uint256 amount,
        address controller
    ) external returns (uint256) {
        /* Initialize shares, remaining amount and redemption IDs */
        uint256 shares;
        uint256 remainingAmount = amount;
        uint256[] memory redemptionIds = redemptionState_.redemptionIds[controller].values();

        /* Iterate through redemption IDs */
        for (uint256 i; i < redemptionIds.length && remainingAmount > 0; i++) {
            /* Look up redemption */
            IStakedUSDai.Redemption storage redemption_ = redemptionState_.redemptions[redemptionIds[i]];

            /* Skip if redemption amount is 0 */
            if (redemption_.withdrawableAmount == 0) continue;

            /* Compute amount to withdraw */
            uint256 amountToWithdraw = Math.min(remainingAmount, redemption_.withdrawableAmount);

            /* Compute shares to redeem */
            uint256 sharesToRedeem = amountToWithdraw == redemption_.withdrawableAmount
                ? redemption_.redeemableShares
                : Math.mulDiv(amountToWithdraw, redemption_.redeemableShares, redemption_.withdrawableAmount);

            /* Update redemption state */
            redemption_.withdrawableAmount -= amountToWithdraw;
            redemption_.redeemableShares -= sharesToRedeem;

            /* Update remaining amount and shares */
            remainingAmount -= amountToWithdraw;
            shares += sharesToRedeem;

            /* If redemption is fully serviced and all shares have been redeemed, */
            /* remove redemption ID */
            if (redemption_.pendingShares == 0 && redemption_.redeemableShares == 0) {
                redemptionState_.redemptionIds[controller].remove(redemptionIds[i]);
            }
        }

        /* Validate withdrawal completed */
        if (remainingAmount != 0) revert IStakedUSDai.InvalidRedemptionState();

        /* Update redemption balance */
        redemptionState_.balance -= amount;

        return shares;
    }

    /**
     * @notice Redeem shares
     * @param redemptionState_ Redemption state
     * @param shares Shares to redeem
     * @param controller Controller address
     * @return Amount redeemed
     */
    function _redeem(
        StakedUSDaiStorage.RedemptionState storage redemptionState_,
        uint256 shares,
        address controller
    ) external returns (uint256) {
        /* Initialize amount, remaining shares and redemption IDs */
        uint256 amount;
        uint256 remainingShares = shares;
        uint256[] memory redemptionIds = redemptionState_.redemptionIds[controller].values();

        /* Iterate through redemption IDs */
        for (uint256 i; i < redemptionIds.length && remainingShares > 0; i++) {
            /* Look up redemption */
            IStakedUSDai.Redemption storage redemption_ = redemptionState_.redemptions[redemptionIds[i]];

            /* Skip if redemption amount is 0 */
            if (redemption_.redeemableShares == 0) continue;

            /* Compute shares to redeem */
            uint256 sharesToRedeem = Math.min(remainingShares, redemption_.redeemableShares);

            /* Compute amount to withdraw */
            uint256 amountToWithdraw = sharesToRedeem == redemption_.redeemableShares
                ? redemption_.withdrawableAmount
                : Math.mulDiv(sharesToRedeem, redemption_.withdrawableAmount, redemption_.redeemableShares);

            /* Update redemption state */
            redemption_.withdrawableAmount -= amountToWithdraw;
            redemption_.redeemableShares -= sharesToRedeem;

            /* Update remaining shares and amount */
            remainingShares -= sharesToRedeem;
            amount += amountToWithdraw;

            /* If redemption is fully serviced and all shares have been redeemed, */
            /* remove redemption ID */
            if (redemption_.pendingShares == 0 && redemption_.withdrawableAmount == 0) {
                redemptionState_.redemptionIds[controller].remove(redemptionIds[i]);
            }
        }

        /* Validate redemption completed */
        if (remainingShares != 0) revert IStakedUSDai.InvalidRedemptionState();

        /* Update redemption balance */
        redemptionState_.balance -= amount;

        return amount;
    }

    /**
     * @notice Request redeem
     * @param redemptionState_ Redemption state
     * @param genesisTimestamp Genesis timestamp
     * @param shares Shares to redeem
     * @param controller Controller address
     * @return Redemption ID
     */
    function _requestRedeem(
        StakedUSDaiStorage.RedemptionState storage redemptionState_,
        uint64 genesisTimestamp,
        uint256 shares,
        address controller
    ) external returns (uint256) {
        /* Validate active redemptions count is less than max allowed */
        if (redemptionState_.redemptionIds[controller].length() == MAX_ACTIVE_REDEMPTIONS_COUNT) {
            revert IStakedUSDai.InvalidRedemptionState();
        }

        /* Validate shares are greater than minimum redemption shares */
        if (shares < MIN_REDEMPTION_SHARES) revert IStakedUSDai.InvalidAmount();

        /* Compute redemption timestamp */
        uint64 redemptionTimestamp = _nextRedemptionTimestamp(genesisTimestamp);

        /* Assign redemption ID */
        uint256 redemptionId = ++redemptionState_.index;

        /* Get current tail */
        uint256 tail = redemptionState_.tail;

        /* Update current tail pointer to next redemption ID */
        redemptionState_.redemptions[tail].next = redemptionId;

        /* Update new tail state */
        redemptionState_.redemptions[redemptionId] = IStakedUSDai.Redemption({
            prev: tail,
            next: 0,
            pendingShares: shares,
            redeemableShares: 0,
            withdrawableAmount: 0,
            controller: controller,
            redemptionTimestamp: redemptionTimestamp
        });
        redemptionState_.tail = redemptionId;

        /* Update pending shares */
        redemptionState_.pending += shares;

        /* If head is not set, set it to the new redemption ID */
        if (redemptionState_.head == 0) {
            redemptionState_.head = redemptionId;
        }

        /* Add redemption ID */
        redemptionState_.redemptionIds[controller].add(redemptionId);

        return redemptionId;
    }

    /**
     * @notice Process pending redemptions
     * @param redemptionState_ Redemption state
     * @param shares Shares to process
     * @param redemptionSharePrice_ Redemption share price
     * @return Amount processed, true if all valid redemptions are serviced
     */
    function _processRedemptions(
        StakedUSDaiStorage.RedemptionState storage redemptionState_,
        uint256 shares,
        uint256 redemptionSharePrice_
    ) external returns (uint256, bool) {
        /* Validate shares are available to be serviced */
        if (redemptionState_.pending < shares) {
            revert IStakedUSDai.InvalidRedemptionState();
        }

        /* Get head redemption ID */
        uint256 head = redemptionState_.head;

        /* If head is not set, revert */
        if (head == 0) revert IStakedUSDai.InvalidRedemptionState();

        /* Process redemptions */
        uint256 remainingShares = shares;
        uint256 amountProcessed;
        while (remainingShares > 0 && head != 0) {
            /* Get redemption */
            IStakedUSDai.Redemption storage redemption_ = redemptionState_.redemptions[head];

            /* Validate that redemption is past redemption timestamp */
            if (redemption_.redemptionTimestamp >= block.timestamp) revert IStakedUSDai.InvalidRedemptionState();

            /* Compute shares to fulfill */
            uint256 fulfilledShares = Math.min(redemption_.pendingShares, remainingShares);

            /* Compute amount to fulfill */
            uint256 fulfilledAmount = Math.mulDiv(fulfilledShares, redemptionSharePrice_, FIXED_POINT_SCALE);

            /* Update redemption pending, redeemable shares, and withdrawable amount */
            redemption_.pendingShares -= fulfilledShares;
            redemption_.redeemableShares += fulfilledShares;
            redemption_.withdrawableAmount += fulfilledAmount;

            /* Update remaining shares and amount processed */
            remainingShares -= fulfilledShares;
            amountProcessed += fulfilledAmount;

            /* Emit RedemptionProcessed */
            emit IStakedUSDai.RedemptionProcessed(
                head, redemption_.controller, fulfilledShares, fulfilledAmount, redemption_.pendingShares
            );

            /* If redemption is completely fulfilled, update head */
            if (redemption_.pendingShares == 0) head = redemption_.next;
        }

        /* If there are remaining shares, revert */
        if (remainingShares != 0) revert IStakedUSDai.InvalidRedemptionState();

        /* Update redemption state */
        redemptionState_.head = head;
        redemptionState_.pending -= shares;

        /* If head is 0 or next redemption is not past redemption timestamp, it
         * means all redemptions for the elapsed redemption windows are serviced */
        return (amountProcessed, head == 0 || redemptionState_.redemptions[head].redemptionTimestamp >= block.timestamp);
    }
}
