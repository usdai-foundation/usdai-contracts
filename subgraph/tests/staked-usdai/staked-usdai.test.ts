import { Address, BigInt, Bytes, ethereum } from "@graphprotocol/graph-ts";
import {
  assert,
  beforeEach,
  clearStore,
  createMockedFunction,
  describe,
  test,
} from "matchstick-as";

import {
  handleRedeemRequest,
  handleRedemptionProcessed,
  handleSUSDaiTransfer,
} from "../../src/staked-usdai";
import { Redemption, RedemptionRequest, RedemptionProcessed, SUSDaiStats, SUSDaiDayData } from "../../generated/schema";
import { bytesFromBigInt } from "../../src/utils/misc";
import {
  STAKED_USDAI_ADDRESS,
  createRedeemRequestEvent,
  createRedemptionProcessedEvent,
  createTransferEvent,
} from "./utils";
import { ALICE, BOB, CHARLIE, TestTimestamps, TransferAmounts } from "../usdai/utils";

const SUSDAI_STATS_ID = Bytes.fromUTF8("susdai-stats");

function mockRedemptionSharePrice(price: BigInt, reverts: boolean = false): void {
  const fn = createMockedFunction(
    STAKED_USDAI_ADDRESS,
    "redemptionSharePrice",
    "redemptionSharePrice():(uint256)"
  ).withArgs([]);
  if (reverts) {
    fn.reverts();
  } else {
    fn.returns([ethereum.Value.fromUnsignedBigInt(price)]);
  }
}

describe("StakedUSDai mapping", () => {
  beforeEach(() => clearStore());

  test("handleRedeemRequest writes RedemptionRequest + snapshot", () => {
    mockRedemptionSharePrice(BigInt.fromString("1100000000000000000")); // 1.1e18

    const controller = Address.fromString("0x0000000000000000000000000000000000000001");
    const owner = Address.fromString("0x0000000000000000000000000000000000000002");
    const sender = Address.fromString("0x0000000000000000000000000000000000000003");

    const event = createRedeemRequestEvent(
      controller,
      owner,
      BigInt.fromI32(42),
      sender,
      BigInt.fromString("1000000000000000000"), // 1 sUSDai share
      BigInt.fromI32(1700000000),
      BigInt.fromI32(336209999)
    );
    handleRedeemRequest(event);

    assert.entityCount("RedemptionRequest", 1);
    assert.entityCount("RedemptionSharePriceSnapshot", 1);
  });

  test("handleRedemptionProcessed writes RedemptionProcessed + snapshot", () => {
    mockRedemptionSharePrice(BigInt.fromString("1200000000000000000")); // 1.2e18

    const controller = Address.fromString("0x0000000000000000000000000000000000000004");

    const event = createRedemptionProcessedEvent(
      BigInt.fromI32(42),
      controller,
      BigInt.fromString("500000000000000000"),  // 0.5 shares fulfilled
      BigInt.fromString("600000000000000000"),  // 0.6 USDai paid out
      BigInt.fromString("500000000000000000"),  // 0.5 shares remaining
      BigInt.fromI32(1700001000),
      BigInt.fromI32(336210000)
    );
    handleRedemptionProcessed(event);

    assert.entityCount("RedemptionProcessed", 1);
    assert.entityCount("RedemptionSharePriceSnapshot", 1);
  });

  test("revert on redemptionSharePrice() skips snapshot but keeps request", () => {
    mockRedemptionSharePrice(BigInt.zero(), true);

    const controller = Address.fromString("0x0000000000000000000000000000000000000005");
    const owner = Address.fromString("0x0000000000000000000000000000000000000006");
    const sender = Address.fromString("0x0000000000000000000000000000000000000007");

    const event = createRedeemRequestEvent(
      controller,
      owner,
      BigInt.fromI32(7),
      sender,
      BigInt.fromString("3000000000000000000"),
      BigInt.fromI32(1699000000),
      BigInt.fromI32(336000000)
    );
    handleRedeemRequest(event);

    assert.entityCount("RedemptionRequest", 1);
    assert.entityCount("RedemptionSharePriceSnapshot", 0);
  });
});

describe("SUSDaiStats and SUSDaiDayData", () => {
  beforeEach(() => clearStore());

  test("Single transfer creates SUSDaiStats and SUSDaiDayData", () => {
    const alice = Address.fromString("0x1111111111111111111111111111111111111111");
    const bob = Address.fromString("0x2222222222222222222222222222222222222222");
    const value = BigInt.fromString("1000000000000000000"); // 1e18
    const timestamp = BigInt.fromI32(1704067200); // 2024-01-01 00:00:00 UTC

    const event = createTransferEvent(alice, bob, value, timestamp);
    handleSUSDaiTransfer(event);

    const statsId = Bytes.fromUTF8("susdai-stats");
    const stats = SUSDaiStats.load(statsId);
    assert.assertNotNull(stats);
    assert.bigIntEquals(value, stats!.totalVolume);
    assert.bigIntEquals(BigInt.fromI32(1), stats!.transferCount);

    const dayId = Bytes.fromUTF8("2024-01-01");
    const dayData = SUSDaiDayData.load(dayId);
    assert.assertNotNull(dayData);
    assert.bigIntEquals(value, dayData!.volume);
    assert.bigIntEquals(BigInt.fromI32(1), dayData!.transferCount);
    assert.stringEquals("2024-01-01", dayData!.date);
  });

  test("Two transfers on same day aggregate correctly", () => {
    const alice = Address.fromString("0x1111111111111111111111111111111111111111");
    const bob = Address.fromString("0x2222222222222222222222222222222222222222");
    const value1 = BigInt.fromString("1000000000000000000"); // 1e18
    const value2 = BigInt.fromString("2000000000000000000"); // 2e18
    const timestamp = BigInt.fromI32(1704067200); // 2024-01-01 00:00:00 UTC

    const event1 = createTransferEvent(alice, bob, value1, timestamp);
    const event2 = createTransferEvent(bob, alice, value2, timestamp);

    handleSUSDaiTransfer(event1);
    handleSUSDaiTransfer(event2);

    const statsId = Bytes.fromUTF8("susdai-stats");
    const stats = SUSDaiStats.load(statsId);
    assert.assertNotNull(stats);
    assert.bigIntEquals(value1.plus(value2), stats!.totalVolume);
    assert.bigIntEquals(BigInt.fromI32(2), stats!.transferCount);

    const dayId = Bytes.fromUTF8("2024-01-01");
    const dayData = SUSDaiDayData.load(dayId);
    assert.assertNotNull(dayData);
    assert.bigIntEquals(value1.plus(value2), dayData!.volume);
    assert.bigIntEquals(BigInt.fromI32(2), dayData!.transferCount);
  });
});

describe("Integration Tests", () => {
  beforeEach(() => {
    clearStore();
  });

  test("Total stats volume equals sum of daily volumes", () => {
    const jan1Event = createTransferEvent(ALICE, BOB, TransferAmounts.ONE_HUNDRED, TestTimestamps.JAN_2024_START);
    const jan15Event = createTransferEvent(BOB, CHARLIE, TransferAmounts.ONE_THOUSAND, TestTimestamps.JAN_2024_MID);
    const jan31Event = createTransferEvent(CHARLIE, ALICE, TransferAmounts.ONE_MILLION, TestTimestamps.JAN_2024_END);

    handleSUSDaiTransfer(jan1Event);
    handleSUSDaiTransfer(jan15Event);
    handleSUSDaiTransfer(jan31Event);

    const stats = SUSDaiStats.load(SUSDAI_STATS_ID);
    const jan1Data = SUSDaiDayData.load(Bytes.fromUTF8("2024-01-01"));
    const jan15Data = SUSDaiDayData.load(Bytes.fromUTF8("2024-01-15"));
    const jan31Data = SUSDaiDayData.load(Bytes.fromUTF8("2024-01-31"));

    assert.assertNotNull(stats);
    assert.assertNotNull(jan1Data);
    assert.assertNotNull(jan15Data);
    assert.assertNotNull(jan31Data);

    const dailySum = jan1Data!.volume.plus(jan15Data!.volume).plus(jan31Data!.volume);
    assert.bigIntEquals(stats!.totalVolume, dailySum);
  });

  test("Total transfer count equals sum of daily counts", () => {
    handleSUSDaiTransfer(createTransferEvent(ALICE, BOB, TransferAmounts.ONE_HUNDRED, TestTimestamps.JAN_2024_START));
    handleSUSDaiTransfer(createTransferEvent(BOB, CHARLIE, TransferAmounts.ONE_HUNDRED, TestTimestamps.JAN_2024_START));

    handleSUSDaiTransfer(createTransferEvent(CHARLIE, ALICE, TransferAmounts.ONE_HUNDRED, TestTimestamps.JAN_2024_MID));

    const stats = SUSDaiStats.load(SUSDAI_STATS_ID);
    const jan1Data = SUSDaiDayData.load(Bytes.fromUTF8("2024-01-01"));
    const jan15Data = SUSDaiDayData.load(Bytes.fromUTF8("2024-01-15"));

    assert.assertNotNull(stats);
    assert.assertNotNull(jan1Data);
    assert.assertNotNull(jan15Data);

    const dailyCountSum = jan1Data!.transferCount.plus(jan15Data!.transferCount);
    assert.bigIntEquals(stats!.transferCount, dailyCountSum);
    assert.bigIntEquals(BigInt.fromI32(3), stats!.transferCount);
  });
});

describe("Redemption entity", () => {
  beforeEach(() => clearStore());

  test("Single RedeemRequest creates Redemption with correct initial state", () => {
    mockRedemptionSharePrice(BigInt.fromString("1100000000000000000"));

    const controller = Address.fromString("0x0000000000000000000000000000000000000001");
    const owner = Address.fromString("0x0000000000000000000000000000000000000002");
    const sender = Address.fromString("0x0000000000000000000000000000000000000003");
    const requestId = BigInt.fromI32(42);
    const shares = BigInt.fromString("1000000000000000000");
    const timestamp = BigInt.fromI32(1700000000);
    const blockNumber = BigInt.fromI32(336209999);

    const event = createRedeemRequestEvent(
      controller,
      owner,
      requestId,
      sender,
      shares,
      timestamp,
      blockNumber
    );
    handleRedeemRequest(event);

    const redemptionId = bytesFromBigInt(requestId);
    const redemption = Redemption.load(redemptionId);

    assert.assertNotNull(redemption);
    assert.bigIntEquals(requestId, redemption!.redemptionId);
    assert.bytesEquals(controller, redemption!.controller);
    assert.bytesEquals(owner, redemption!.owner);
    assert.bytesEquals(sender, redemption!.sender);
    assert.bigIntEquals(shares, redemption!.requestedShares);
    assert.bigIntEquals(shares, redemption!.pendingShares);
    assert.bigIntEquals(BigInt.fromI32(0), redemption!.fulfilledShares);
    assert.bigIntEquals(BigInt.fromI32(0), redemption!.fulfilledAmount);
    assert.booleanEquals(true, redemption!.active);
    assert.bigIntEquals(blockNumber, redemption!.requestedAtBlock);
    assert.bigIntEquals(timestamp, redemption!.requestedAtTimestamp);
    assert.bigIntEquals(blockNumber, redemption!.lastUpdatedBlock);
    assert.bigIntEquals(timestamp, redemption!.lastUpdatedTimestamp);
  });

  test("Partial RedemptionProcessed updates Redemption correctly", () => {
    mockRedemptionSharePrice(BigInt.fromString("1100000000000000000"));

    const controller = Address.fromString("0x0000000000000000000000000000000000000001");
    const owner = Address.fromString("0x0000000000000000000000000000000000000002");
    const sender = Address.fromString("0x0000000000000000000000000000000000000003");
    const requestId = BigInt.fromI32(99);
    const requestedShares = BigInt.fromString("1000000000000000000");
    const requestTimestamp = BigInt.fromI32(1700000000);
    const requestBlockNumber = BigInt.fromI32(336209999);

    const requestEvent = createRedeemRequestEvent(
      controller,
      owner,
      requestId,
      sender,
      requestedShares,
      requestTimestamp,
      requestBlockNumber
    );
    handleRedeemRequest(requestEvent);

    const fulfilledShares = BigInt.fromString("400000000000000000");
    const amount = BigInt.fromString("400000000000000000");
    const processTimestamp = BigInt.fromI32(1700001000);
    const processBlockNumber = BigInt.fromI32(336210000);

    const processedEvent = createRedemptionProcessedEvent(
      requestId,
      controller,
      fulfilledShares,
      amount,
      BigInt.fromString("600000000000000000"), // pendingShares in event (unused, we compute from Redemption)
      processTimestamp,
      processBlockNumber
    );
    handleRedemptionProcessed(processedEvent);

    const redemptionId = bytesFromBigInt(requestId);
    const redemption = Redemption.load(redemptionId);

    assert.assertNotNull(redemption);
    assert.bigIntEquals(BigInt.fromString("600000000000000000"), redemption!.pendingShares);
    assert.bigIntEquals(fulfilledShares, redemption!.fulfilledShares);
    assert.bigIntEquals(amount, redemption!.fulfilledAmount);
    assert.booleanEquals(true, redemption!.active);
    assert.bigIntEquals(processBlockNumber, redemption!.lastUpdatedBlock);
    assert.bigIntEquals(processTimestamp, redemption!.lastUpdatedTimestamp);
  });

  test("Full RedemptionProcessed in one go marks Redemption as inactive", () => {
    mockRedemptionSharePrice(BigInt.fromString("1100000000000000000"));

    const controller = Address.fromString("0x0000000000000000000000000000000000000004");
    const owner = Address.fromString("0x0000000000000000000000000000000000000005");
    const sender = Address.fromString("0x0000000000000000000000000000000000000006");
    const requestId = BigInt.fromI32(100);
    const shares = BigInt.fromString("1000000000000000000");
    const requestTimestamp = BigInt.fromI32(1700000000);
    const requestBlockNumber = BigInt.fromI32(336209999);

    const requestEvent = createRedeemRequestEvent(
      controller,
      owner,
      requestId,
      sender,
      shares,
      requestTimestamp,
      requestBlockNumber
    );
    handleRedeemRequest(requestEvent);

    const fulfilledShares = shares;
    const amount = shares;
    const processTimestamp = BigInt.fromI32(1700001000);
    const processBlockNumber = BigInt.fromI32(336210000);

    const processedEvent = createRedemptionProcessedEvent(
      requestId,
      controller,
      fulfilledShares,
      amount,
      BigInt.fromI32(0),
      processTimestamp,
      processBlockNumber
    );
    handleRedemptionProcessed(processedEvent);

    const redemptionId = bytesFromBigInt(requestId);
    const redemption = Redemption.load(redemptionId);

    assert.assertNotNull(redemption);
    assert.bigIntEquals(BigInt.fromI32(0), redemption!.pendingShares);
    assert.bigIntEquals(fulfilledShares, redemption!.fulfilledShares);
    assert.bigIntEquals(amount, redemption!.fulfilledAmount);
    assert.booleanEquals(false, redemption!.active);
  });

  test("Two partial RedemptionProcessed events accumulate correctly", () => {
    mockRedemptionSharePrice(BigInt.fromString("1100000000000000000"));

    const controller = Address.fromString("0x0000000000000000000000000000000000000007");
    const owner = Address.fromString("0x0000000000000000000000000000000000000008");
    const sender = Address.fromString("0x0000000000000000000000000000000000000009");
    const requestId = BigInt.fromI32(101);
    const shares = BigInt.fromString("1000000000000000000");
    const requestTimestamp = BigInt.fromI32(1700000000);
    const requestBlockNumber = BigInt.fromI32(336209999);

    const requestEvent = createRedeemRequestEvent(
      controller,
      owner,
      requestId,
      sender,
      shares,
      requestTimestamp,
      requestBlockNumber
    );
    handleRedeemRequest(requestEvent);

    const fulfilledShares1 = BigInt.fromString("400000000000000000");
    const amount1 = BigInt.fromString("400000000000000000");
    const processTimestamp1 = BigInt.fromI32(1700001000);
    const processBlockNumber1 = BigInt.fromI32(336210000);

    const processedEvent1 = createRedemptionProcessedEvent(
      requestId,
      controller,
      fulfilledShares1,
      amount1,
      BigInt.fromString("600000000000000000"),
      processTimestamp1,
      processBlockNumber1
    );
    handleRedemptionProcessed(processedEvent1);

    const fulfilledShares2 = BigInt.fromString("600000000000000000");
    const amount2 = BigInt.fromString("600000000000000000");
    const processTimestamp2 = BigInt.fromI32(1700002000);
    const processBlockNumber2 = BigInt.fromI32(336210001);

    const processedEvent2 = createRedemptionProcessedEvent(
      requestId,
      controller,
      fulfilledShares2,
      amount2,
      BigInt.fromI32(0),
      processTimestamp2,
      processBlockNumber2
    );
    handleRedemptionProcessed(processedEvent2);

    const redemptionId = bytesFromBigInt(requestId);
    const redemption = Redemption.load(redemptionId);

    assert.assertNotNull(redemption);
    assert.bigIntEquals(BigInt.fromI32(0), redemption!.pendingShares);
    assert.bigIntEquals(shares, redemption!.fulfilledShares);
    assert.bigIntEquals(shares, redemption!.fulfilledAmount);
    assert.booleanEquals(false, redemption!.active);
    assert.bigIntEquals(processBlockNumber2, redemption!.lastUpdatedBlock);
    assert.bigIntEquals(processTimestamp2, redemption!.lastUpdatedTimestamp);
  });

  test("RedemptionProcessed without prior Request is defensive", () => {
    mockRedemptionSharePrice(BigInt.fromString("1100000000000000000"));

    const controller = Address.fromString("0x000000000000000000000000000000000000000a");
    const orphanedRedemptionId = BigInt.fromI32(999);
    const fulfilledShares = BigInt.fromString("100000000000000000");
    const amount = BigInt.fromString("100000000000000000");
    const timestamp = BigInt.fromI32(1700000000);
    const blockNumber = BigInt.fromI32(336209999);

    const orphanedEvent = createRedemptionProcessedEvent(
      orphanedRedemptionId,
      controller,
      fulfilledShares,
      amount,
      BigInt.fromI32(0),
      timestamp,
      blockNumber
    );
    handleRedemptionProcessed(orphanedEvent);

    const redemptionId = bytesFromBigInt(orphanedRedemptionId);
    const redemption = Redemption.load(redemptionId);

    assert.assertNull(redemption);
    // RedemptionProcessed event itself is still written (immutable history)
    assert.entityCount("RedemptionProcessed", 1);
  });

  test("RedemptionRequest and RedemptionProcessed entities are still written alongside Redemption", () => {
    mockRedemptionSharePrice(BigInt.fromString("1100000000000000000"));

    const controller = Address.fromString("0x000000000000000000000000000000000000000b");
    const owner = Address.fromString("0x000000000000000000000000000000000000000c");
    const sender = Address.fromString("0x000000000000000000000000000000000000000d");
    const requestId = BigInt.fromI32(102);
    const shares = BigInt.fromString("1000000000000000000");
    const requestTimestamp = BigInt.fromI32(1700000000);
    const requestBlockNumber = BigInt.fromI32(336209999);

    const requestEvent = createRedeemRequestEvent(
      controller,
      owner,
      requestId,
      sender,
      shares,
      requestTimestamp,
      requestBlockNumber
    );
    handleRedeemRequest(requestEvent);

    // Verify RedemptionRequest and Redemption were created
    assert.entityCount("RedemptionRequest", 1);
    assert.entityCount("Redemption", 1);

    const fulfilledShares = BigInt.fromString("500000000000000000");
    const amount = BigInt.fromString("500000000000000000");
    const processTimestamp = BigInt.fromI32(1700001000);
    const processBlockNumber = BigInt.fromI32(336210000);

    const processedEvent = createRedemptionProcessedEvent(
      requestId,
      controller,
      fulfilledShares,
      amount,
      BigInt.fromString("500000000000000000"),
      processTimestamp,
      processBlockNumber
    );
    handleRedemptionProcessed(processedEvent);

    // All three entities exist after processing
    assert.entityCount("RedemptionRequest", 1);
    assert.entityCount("RedemptionProcessed", 1);
    assert.entityCount("Redemption", 1);

    // Verify Redemption was updated
    const redemptionId = bytesFromBigInt(requestId);
    const redemption = Redemption.load(redemptionId);
    assert.assertNotNull(redemption);
    assert.bigIntEquals(BigInt.fromString("500000000000000000"), redemption!.pendingShares);
  });
});
