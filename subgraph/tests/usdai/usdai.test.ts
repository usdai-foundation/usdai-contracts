import { BigInt, Bytes } from "@graphprotocol/graph-ts";
import { assert, beforeEach, clearStore, describe, test } from "matchstick-as";
import { USDaiDayData, USDaiStats } from "../../generated/schema";
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

describe("USDaiDayData", () => {
  beforeEach(() => {
    clearStore();
  });

  test("Day ID format is YYYY-MM-DD with leading zeros", () => {
    const event = createTransferEvent(ALICE, BOB, TransferAmounts.ONE_HUNDRED, TestTimestamps.JAN_2024_START);

    handleTransfer(event);

    const dayId = Bytes.fromUTF8("2024-01-01");
    const dayData = USDaiDayData.load(dayId);
    assert.assertNotNull(dayData);
  });

  test("Correct date/timestamp fields set", () => {
    const event = createTransferEvent(ALICE, BOB, TransferAmounts.ONE_HUNDRED, TestTimestamps.JAN_2024_START);

    handleTransfer(event);

    const dayId = Bytes.fromUTF8("2024-01-01");
    const dayData = USDaiDayData.load(dayId);
    assert.assertNotNull(dayData);
    assert.stringEquals("2024-01-01", dayData!.date);
    assert.bigIntEquals(BigInt.fromI32(1704067200), dayData!.timestamp);
  });

  test("Same-day transfers aggregate to single entity", () => {
    const event1 = createTransferEvent(ALICE, BOB, TransferAmounts.ONE_HUNDRED, TestTimestamps.JAN_2024_START);
    const event2 = createTransferEvent(BOB, CHARLIE, TransferAmounts.ONE_THOUSAND, TestTimestamps.JAN_2024_START);
    const event3 = createTransferEvent(CHARLIE, ALICE, TransferAmounts.ONE_HUNDRED, TestTimestamps.JAN_2024_START);

    handleTransfer(event1);
    handleTransfer(event2);
    handleTransfer(event3);

    const dayId = Bytes.fromUTF8("2024-01-01");
    const dayData = USDaiDayData.load(dayId);
    assert.assertNotNull(dayData);

    const expectedVolume = TransferAmounts.ONE_HUNDRED.plus(TransferAmounts.ONE_THOUSAND).plus(
      TransferAmounts.ONE_HUNDRED,
    );
    assert.bigIntEquals(expectedVolume, dayData!.volume);
    assert.bigIntEquals(BigInt.fromI32(3), dayData!.transferCount);
  });

  test("Different days create separate entities", () => {
    const jan15Event = createTransferEvent(ALICE, BOB, TransferAmounts.ONE_HUNDRED, TestTimestamps.JAN_2024_MID);
    const jan16Event = createTransferEvent(BOB, CHARLIE, TransferAmounts.ONE_THOUSAND, TestTimestamps.JAN_2024_END);

    handleTransfer(jan15Event);
    handleTransfer(jan16Event);

    const jan15DayId = Bytes.fromUTF8("2024-01-15");
    const jan31DayId = Bytes.fromUTF8("2024-01-31");

    const jan15Data = USDaiDayData.load(jan15DayId);
    const jan31Data = USDaiDayData.load(jan31DayId);

    assert.assertNotNull(jan15Data);
    assert.assertNotNull(jan31Data);

    assert.bigIntEquals(TransferAmounts.ONE_HUNDRED, jan15Data!.volume);
    assert.bigIntEquals(TransferAmounts.ONE_THOUSAND, jan31Data!.volume);

    assert.stringEquals("2024-01-15", jan15Data!.date);
    assert.stringEquals("2024-01-31", jan31Data!.date);
  });

  test("Day boundary creates separate entities", () => {
    const jan31Event = createTransferEvent(ALICE, BOB, TransferAmounts.ONE_HUNDRED, TestTimestamps.JAN_2024_END);
    const feb1Event = createTransferEvent(BOB, CHARLIE, TransferAmounts.ONE_THOUSAND, TestTimestamps.FEB_2024_START);

    handleTransfer(jan31Event);
    handleTransfer(feb1Event);

    const jan31Id = Bytes.fromUTF8("2024-01-31");
    const feb1Id = Bytes.fromUTF8("2024-02-01");

    const jan31Data = USDaiDayData.load(jan31Id);
    const feb1Data = USDaiDayData.load(feb1Id);

    assert.assertNotNull(jan31Data);
    assert.assertNotNull(feb1Data);

    assert.stringEquals("2024-01-31", jan31Data!.date);
    assert.stringEquals("2024-02-01", feb1Data!.date);
  });

  test("Leap year February 29 handled correctly", () => {
    const leapDayEvent = createTransferEvent(ALICE, BOB, TransferAmounts.ONE_HUNDRED, TestTimestamps.FEB_2024_LEAP_DAY);

    handleTransfer(leapDayEvent);

    const febDayId = Bytes.fromUTF8("2024-02-29");
    const febData = USDaiDayData.load(febDayId);

    assert.assertNotNull(febData);
    assert.stringEquals("2024-02-29", febData!.date);
  });

  test("Year boundary creates separate entities", () => {
    const dec31Event = createTransferEvent(ALICE, BOB, TransferAmounts.ONE_HUNDRED, TestTimestamps.DEC_2024_END);
    const jan1Event = createTransferEvent(BOB, CHARLIE, TransferAmounts.ONE_THOUSAND, TestTimestamps.JAN_2025_START);

    handleTransfer(dec31Event);
    handleTransfer(jan1Event);

    const dec31Id = Bytes.fromUTF8("2024-12-31");
    const jan1Id = Bytes.fromUTF8("2025-01-01");

    const dec31Data = USDaiDayData.load(dec31Id);
    const jan1Data = USDaiDayData.load(jan1Id);

    assert.assertNotNull(dec31Data);
    assert.assertNotNull(jan1Data);

    assert.stringEquals("2024-12-31", dec31Data!.date);
    assert.stringEquals("2025-01-01", jan1Data!.date);
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

    handleTransfer(jan1Event);
    handleTransfer(jan15Event);
    handleTransfer(jan31Event);

    const stats = USDaiStats.load(STATS_ID);
    const jan1Data = USDaiDayData.load(Bytes.fromUTF8("2024-01-01"));
    const jan15Data = USDaiDayData.load(Bytes.fromUTF8("2024-01-15"));
    const jan31Data = USDaiDayData.load(Bytes.fromUTF8("2024-01-31"));

    assert.assertNotNull(stats);
    assert.assertNotNull(jan1Data);
    assert.assertNotNull(jan15Data);
    assert.assertNotNull(jan31Data);

    const dailySum = jan1Data!.volume.plus(jan15Data!.volume).plus(jan31Data!.volume);
    assert.bigIntEquals(stats!.totalVolume, dailySum);
  });

  test("Total transfer count equals sum of daily counts", () => {
    handleTransfer(createTransferEvent(ALICE, BOB, TransferAmounts.ONE_HUNDRED, TestTimestamps.JAN_2024_START));
    handleTransfer(createTransferEvent(BOB, CHARLIE, TransferAmounts.ONE_HUNDRED, TestTimestamps.JAN_2024_START));

    handleTransfer(createTransferEvent(CHARLIE, ALICE, TransferAmounts.ONE_HUNDRED, TestTimestamps.JAN_2024_MID));

    const stats = USDaiStats.load(STATS_ID);
    const jan1Data = USDaiDayData.load(Bytes.fromUTF8("2024-01-01"));
    const jan15Data = USDaiDayData.load(Bytes.fromUTF8("2024-01-15"));

    assert.assertNotNull(stats);
    assert.assertNotNull(jan1Data);
    assert.assertNotNull(jan15Data);

    const dailyCountSum = jan1Data!.transferCount.plus(jan15Data!.transferCount);
    assert.bigIntEquals(stats!.transferCount, dailyCountSum);
    assert.bigIntEquals(BigInt.fromI32(3), stats!.transferCount);
  });
});
