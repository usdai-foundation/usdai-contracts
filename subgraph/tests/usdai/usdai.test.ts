import { BigInt, Bytes } from "@graphprotocol/graph-ts";
import { assert, beforeEach, clearStore, describe, test } from "matchstick-as";
import { USDaiMonthData, USDaiStats } from "../../generated/schema";
import { handleTransfer } from "../../src/usdai";
import { ALICE, BOB, CHARLIE, createTransferEvent, TestTimestamps, TransferAmounts } from "./utils";

const STATS_ID = Bytes.fromUTF8("stats");

describe("USDaiStats", () => {
  beforeEach(() => {
    clearStore();
  });

  test("First transfer creates entity with correct values", () => {
    const event = createTransferEvent(ALICE, BOB, TransferAmounts.ONE_HUNDRED, TestTimestamps.JAN_2024_START);

    handleTransfer(event);

    const stats = USDaiStats.load(STATS_ID);
    assert.assertNotNull(stats);
    assert.bigIntEquals(TransferAmounts.ONE_HUNDRED, stats!.totalVolume);
    assert.bigIntEquals(BigInt.fromI32(1), stats!.transferCount);
  });

  test("Multiple transfers accumulate totalVolume correctly", () => {
    const event1 = createTransferEvent(ALICE, BOB, TransferAmounts.ONE_HUNDRED, TestTimestamps.JAN_2024_START);
    const event2 = createTransferEvent(BOB, CHARLIE, TransferAmounts.ONE_THOUSAND, TestTimestamps.JAN_2024_MID);

    handleTransfer(event1);
    handleTransfer(event2);

    const stats = USDaiStats.load(STATS_ID);
    assert.assertNotNull(stats);

    const expectedVolume = TransferAmounts.ONE_HUNDRED.plus(TransferAmounts.ONE_THOUSAND);
    assert.bigIntEquals(expectedVolume, stats!.totalVolume);
  });

  test("Transfer count increments correctly", () => {
    const event1 = createTransferEvent(ALICE, BOB, TransferAmounts.ONE_HUNDRED, TestTimestamps.JAN_2024_START);
    const event2 = createTransferEvent(BOB, CHARLIE, TransferAmounts.ONE_HUNDRED, TestTimestamps.JAN_2024_MID);
    const event3 = createTransferEvent(CHARLIE, ALICE, TransferAmounts.ONE_HUNDRED, TestTimestamps.JAN_2024_END);

    handleTransfer(event1);
    handleTransfer(event2);
    handleTransfer(event3);

    const stats = USDaiStats.load(STATS_ID);
    assert.assertNotNull(stats);
    assert.bigIntEquals(BigInt.fromI32(3), stats!.transferCount);
  });

  test("Zero-value transfers are counted but add zero volume", () => {
    const event1 = createTransferEvent(ALICE, BOB, TransferAmounts.ONE_HUNDRED, TestTimestamps.JAN_2024_START);
    const zeroEvent = createTransferEvent(BOB, CHARLIE, TransferAmounts.ZERO, TestTimestamps.JAN_2024_MID);

    handleTransfer(event1);
    handleTransfer(zeroEvent);

    const stats = USDaiStats.load(STATS_ID);
    assert.assertNotNull(stats);
    assert.bigIntEquals(TransferAmounts.ONE_HUNDRED, stats!.totalVolume);
    assert.bigIntEquals(BigInt.fromI32(2), stats!.transferCount);
  });

  test("Large amounts handled correctly", () => {
    const event = createTransferEvent(ALICE, BOB, TransferAmounts.ONE_MILLION, TestTimestamps.JAN_2024_START);

    handleTransfer(event);

    const stats = USDaiStats.load(STATS_ID);
    assert.assertNotNull(stats);
    assert.bigIntEquals(TransferAmounts.ONE_MILLION, stats!.totalVolume);
  });

  test("Minimum amount (1 wei) handled correctly", () => {
    const event = createTransferEvent(ALICE, BOB, TransferAmounts.ONE_WEI, TestTimestamps.JAN_2024_START);

    handleTransfer(event);

    const stats = USDaiStats.load(STATS_ID);
    assert.assertNotNull(stats);
    assert.bigIntEquals(TransferAmounts.ONE_WEI, stats!.totalVolume);
  });
});

describe("USDaiMonthData", () => {
  beforeEach(() => {
    clearStore();
  });

  test("Month ID format is YYYY-MM with leading zeros", () => {
    const event = createTransferEvent(ALICE, BOB, TransferAmounts.ONE_HUNDRED, TestTimestamps.JAN_2024_START);

    handleTransfer(event);

    const monthId = Bytes.fromUTF8("2024-01");
    const monthData = USDaiMonthData.load(monthId);
    assert.assertNotNull(monthData);
  });

  test("Correct year/month/timestamp fields set", () => {
    const event = createTransferEvent(ALICE, BOB, TransferAmounts.ONE_HUNDRED, TestTimestamps.JAN_2024_START);

    handleTransfer(event);

    const monthId = Bytes.fromUTF8("2024-01");
    const monthData = USDaiMonthData.load(monthId);
    assert.assertNotNull(monthData);
    assert.i32Equals(2024, monthData!.year);
    assert.i32Equals(1, monthData!.month);
    // January 2024 start timestamp
    assert.bigIntEquals(BigInt.fromI32(1704067200), monthData!.timestamp);
  });

  test("Same-month transfers aggregate to single entity", () => {
    const event1 = createTransferEvent(ALICE, BOB, TransferAmounts.ONE_HUNDRED, TestTimestamps.JAN_2024_START);
    const event2 = createTransferEvent(BOB, CHARLIE, TransferAmounts.ONE_THOUSAND, TestTimestamps.JAN_2024_MID);
    const event3 = createTransferEvent(CHARLIE, ALICE, TransferAmounts.ONE_HUNDRED, TestTimestamps.JAN_2024_END);

    handleTransfer(event1);
    handleTransfer(event2);
    handleTransfer(event3);

    const monthId = Bytes.fromUTF8("2024-01");
    const monthData = USDaiMonthData.load(monthId);
    assert.assertNotNull(monthData);

    const expectedVolume = TransferAmounts.ONE_HUNDRED.plus(TransferAmounts.ONE_THOUSAND).plus(
      TransferAmounts.ONE_HUNDRED,
    );
    assert.bigIntEquals(expectedVolume, monthData!.volume);
    assert.bigIntEquals(BigInt.fromI32(3), monthData!.transferCount);
  });

  test("Different months create separate entities", () => {
    const janEvent = createTransferEvent(ALICE, BOB, TransferAmounts.ONE_HUNDRED, TestTimestamps.JAN_2024_START);
    const febEvent = createTransferEvent(BOB, CHARLIE, TransferAmounts.ONE_THOUSAND, TestTimestamps.FEB_2024_START);

    handleTransfer(janEvent);
    handleTransfer(febEvent);

    const janMonthId = Bytes.fromUTF8("2024-01");
    const febMonthId = Bytes.fromUTF8("2024-02");

    const janData = USDaiMonthData.load(janMonthId);
    const febData = USDaiMonthData.load(febMonthId);

    assert.assertNotNull(janData);
    assert.assertNotNull(febData);

    assert.bigIntEquals(TransferAmounts.ONE_HUNDRED, janData!.volume);
    assert.bigIntEquals(TransferAmounts.ONE_THOUSAND, febData!.volume);

    assert.i32Equals(1, janData!.month);
    assert.i32Equals(2, febData!.month);
  });

  test("Year boundary creates separate entities", () => {
    const dec2024Event = createTransferEvent(ALICE, BOB, TransferAmounts.ONE_HUNDRED, TestTimestamps.DEC_2024_END);
    const jan2025Event = createTransferEvent(BOB, CHARLIE, TransferAmounts.ONE_THOUSAND, TestTimestamps.JAN_2025_START);

    handleTransfer(dec2024Event);
    handleTransfer(jan2025Event);

    const dec2024Id = Bytes.fromUTF8("2024-12");
    const jan2025Id = Bytes.fromUTF8("2025-01");

    const dec2024Data = USDaiMonthData.load(dec2024Id);
    const jan2025Data = USDaiMonthData.load(jan2025Id);

    assert.assertNotNull(dec2024Data);
    assert.assertNotNull(jan2025Data);

    assert.i32Equals(2024, dec2024Data!.year);
    assert.i32Equals(12, dec2024Data!.month);

    assert.i32Equals(2025, jan2025Data!.year);
    assert.i32Equals(1, jan2025Data!.month);
  });

  test("Leap year February handled correctly", () => {
    const leapDayEvent = createTransferEvent(ALICE, BOB, TransferAmounts.ONE_HUNDRED, TestTimestamps.FEB_2024_LEAP_DAY);

    handleTransfer(leapDayEvent);

    const febMonthId = Bytes.fromUTF8("2024-02");
    const febData = USDaiMonthData.load(febMonthId);

    assert.assertNotNull(febData);
    assert.i32Equals(2024, febData!.year);
    assert.i32Equals(2, febData!.month);
  });

  test("Double-digit months work correctly", () => {
    const event = createTransferEvent(ALICE, BOB, TransferAmounts.ONE_HUNDRED, TestTimestamps.DEC_2024_END);

    handleTransfer(event);

    const monthId = Bytes.fromUTF8("2024-12");
    const monthData = USDaiMonthData.load(monthId);
    assert.assertNotNull(monthData);
    assert.i32Equals(12, monthData!.month);
  });
});

describe("Integration Tests", () => {
  beforeEach(() => {
    clearStore();
  });

  test("Total stats volume equals sum of monthly volumes", () => {
    const janEvent = createTransferEvent(ALICE, BOB, TransferAmounts.ONE_HUNDRED, TestTimestamps.JAN_2024_START);
    const febEvent = createTransferEvent(BOB, CHARLIE, TransferAmounts.ONE_THOUSAND, TestTimestamps.FEB_2024_START);
    const marEvent = createTransferEvent(CHARLIE, ALICE, TransferAmounts.ONE_MILLION, TestTimestamps.MAR_2024_START);

    handleTransfer(janEvent);
    handleTransfer(febEvent);
    handleTransfer(marEvent);

    const stats = USDaiStats.load(STATS_ID);
    const janData = USDaiMonthData.load(Bytes.fromUTF8("2024-01"));
    const febData = USDaiMonthData.load(Bytes.fromUTF8("2024-02"));
    const marData = USDaiMonthData.load(Bytes.fromUTF8("2024-03"));

    assert.assertNotNull(stats);
    assert.assertNotNull(janData);
    assert.assertNotNull(febData);
    assert.assertNotNull(marData);

    const monthlySum = janData!.volume.plus(febData!.volume).plus(marData!.volume);
    assert.bigIntEquals(stats!.totalVolume, monthlySum);
  });

  test("Total transfer count equals sum of monthly counts", () => {
    // 2 transfers in January
    handleTransfer(createTransferEvent(ALICE, BOB, TransferAmounts.ONE_HUNDRED, TestTimestamps.JAN_2024_START));
    handleTransfer(createTransferEvent(BOB, CHARLIE, TransferAmounts.ONE_HUNDRED, TestTimestamps.JAN_2024_MID));

    // 1 transfer in February
    handleTransfer(createTransferEvent(CHARLIE, ALICE, TransferAmounts.ONE_HUNDRED, TestTimestamps.FEB_2024_START));

    const stats = USDaiStats.load(STATS_ID);
    const janData = USDaiMonthData.load(Bytes.fromUTF8("2024-01"));
    const febData = USDaiMonthData.load(Bytes.fromUTF8("2024-02"));

    assert.assertNotNull(stats);
    assert.assertNotNull(janData);
    assert.assertNotNull(febData);

    const monthlyCountSum = janData!.transferCount.plus(febData!.transferCount);
    assert.bigIntEquals(stats!.transferCount, monthlyCountSum);
    assert.bigIntEquals(BigInt.fromI32(3), stats!.transferCount);
  });
});
