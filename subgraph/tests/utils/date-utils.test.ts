import { assert, describe, test } from "matchstick-as";
import { BigInt, Bytes } from "@graphprotocol/graph-ts";
import { getYearAndMonth, getMonthStartTimestamp, createMonthId } from "../../src/utils";

describe("getYearAndMonth", () => {
  test("Unix epoch returns [1970, 1]", () => {
    const result = getYearAndMonth(BigInt.fromI32(0));
    assert.i32Equals(1970, result[0]);
    assert.i32Equals(1, result[1]);
  });

  test("Known date: 2024-01-01 00:00:00 UTC", () => {
    // January 1, 2024 00:00:00 UTC = 1704067200
    const result = getYearAndMonth(BigInt.fromI32(1704067200));
    assert.i32Equals(2024, result[0]);
    assert.i32Equals(1, result[1]);
  });

  test("Known date: 2024-06-15 12:00:00 UTC (mid-year)", () => {
    // June 15, 2024 12:00:00 UTC = 1718452800
    const result = getYearAndMonth(BigInt.fromI32(1718452800));
    assert.i32Equals(2024, result[0]);
    assert.i32Equals(6, result[1]);
  });

  test("Known date: 2024-12-31 23:59:59 UTC", () => {
    // December 31, 2024 23:59:59 UTC = 1735689599
    const result = getYearAndMonth(BigInt.fromI32(1735689599));
    assert.i32Equals(2024, result[0]);
    assert.i32Equals(12, result[1]);
  });

  test("Month boundary: Jan 31 23:59:59 vs Feb 1 00:00:00", () => {
    // January 31, 2024 23:59:59 UTC = 1706745599
    const janEnd = getYearAndMonth(BigInt.fromI32(1706745599));
    assert.i32Equals(2024, janEnd[0]);
    assert.i32Equals(1, janEnd[1]);

    // February 1, 2024 00:00:00 UTC = 1706745600
    const febStart = getYearAndMonth(BigInt.fromI32(1706745600));
    assert.i32Equals(2024, febStart[0]);
    assert.i32Equals(2, febStart[1]);
  });

  test("Year boundary: Dec 31 2024 vs Jan 1 2025", () => {
    // December 31, 2024 23:59:59 UTC = 1735689599
    const dec2024 = getYearAndMonth(BigInt.fromI32(1735689599));
    assert.i32Equals(2024, dec2024[0]);
    assert.i32Equals(12, dec2024[1]);

    // January 1, 2025 00:00:00 UTC = 1735689600
    const jan2025 = getYearAndMonth(BigInt.fromI32(1735689600));
    assert.i32Equals(2025, jan2025[0]);
    assert.i32Equals(1, jan2025[1]);
  });

  test("Leap year: Feb 29 2024", () => {
    // February 29, 2024 12:00:00 UTC = 1709208000
    const result = getYearAndMonth(BigInt.fromI32(1709208000));
    assert.i32Equals(2024, result[0]);
    assert.i32Equals(2, result[1]);
  });

  test("Non-leap year: Feb 28 2023 to Mar 1 2023", () => {
    // February 28, 2023 23:59:59 UTC = 1677628799
    const feb28 = getYearAndMonth(BigInt.fromI32(1677628799));
    assert.i32Equals(2023, feb28[0]);
    assert.i32Equals(2, feb28[1]);

    // March 1, 2023 00:00:00 UTC = 1677628800
    const mar1 = getYearAndMonth(BigInt.fromI32(1677628800));
    assert.i32Equals(2023, mar1[0]);
    assert.i32Equals(3, mar1[1]);
  });

  test("Handles large timestamp (far future)", () => {
    // January 1, 2050 00:00:00 UTC = 2524608000
    const result = getYearAndMonth(BigInt.fromI64(2524608000));
    assert.i32Equals(2050, result[0]);
    assert.i32Equals(1, result[1]);
  });
});

describe("getMonthStartTimestamp", () => {
  test("January 1970 returns 0", () => {
    const result = getMonthStartTimestamp(1970, 1);
    assert.bigIntEquals(BigInt.fromI32(0), result);
  });

  test("January 2024 = 1704067200", () => {
    const result = getMonthStartTimestamp(2024, 1);
    assert.bigIntEquals(BigInt.fromI32(1704067200), result);
  });

  test("February 2024 = 1706745600", () => {
    const result = getMonthStartTimestamp(2024, 2);
    assert.bigIntEquals(BigInt.fromI32(1706745600), result);
  });

  test("March 2024 accounts for leap day", () => {
    // In a leap year, February has 29 days, so March starts on day 60 of the year
    // March 1, 2024 = 1709251200
    const result = getMonthStartTimestamp(2024, 3);
    assert.bigIntEquals(BigInt.fromI32(1709251200), result);
  });

  test("March 2023 (non-leap year)", () => {
    // In non-leap year, February has 28 days, so March starts on day 59 of the year
    // March 1, 2023 = 1677628800
    const result = getMonthStartTimestamp(2023, 3);
    assert.bigIntEquals(BigInt.fromI32(1677628800), result);
  });

  test("December 2024", () => {
    // December 1, 2024 = 1733011200
    const result = getMonthStartTimestamp(2024, 12);
    assert.bigIntEquals(BigInt.fromI32(1733011200), result);
  });

  test("January 2025", () => {
    // January 1, 2025 = 1735689600
    const result = getMonthStartTimestamp(2025, 1);
    assert.bigIntEquals(BigInt.fromI32(1735689600), result);
  });

  test("Consistency: getMonthStartTimestamp output parses back correctly", () => {
    // Get start of June 2024
    const timestamp = getMonthStartTimestamp(2024, 6);
    // Parse it back
    const result = getYearAndMonth(timestamp);
    assert.i32Equals(2024, result[0]);
    assert.i32Equals(6, result[1]);
  });
});

describe("createMonthId", () => {
  test("Single-digit months get leading zero", () => {
    const jan = createMonthId(2024, 1);
    assert.bytesEquals(Bytes.fromUTF8("2024-01"), jan);

    const sep = createMonthId(2024, 9);
    assert.bytesEquals(Bytes.fromUTF8("2024-09"), sep);
  });

  test("Double-digit months work correctly", () => {
    const oct = createMonthId(2024, 10);
    assert.bytesEquals(Bytes.fromUTF8("2024-10"), oct);

    const dec = createMonthId(2024, 12);
    assert.bytesEquals(Bytes.fromUTF8("2024-12"), dec);
  });

  test("IDs are unique per year-month", () => {
    const jan2024 = createMonthId(2024, 1);
    const jan2025 = createMonthId(2025, 1);
    const feb2024 = createMonthId(2024, 2);

    // All should be different
    assert.assertTrue(jan2024.notEqual(jan2025));
    assert.assertTrue(jan2024.notEqual(feb2024));
    assert.assertTrue(jan2025.notEqual(feb2024));
  });

  test("Format is consistent YYYY-MM", () => {
    const id = createMonthId(2030, 7);
    assert.bytesEquals(Bytes.fromUTF8("2030-07"), id);
  });
});
