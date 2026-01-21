import { BigInt, Bytes, ethereum } from "@graphprotocol/graph-ts";

export function bytesFromBigInt(bigInt: BigInt): Bytes {
  return Bytes.fromByteArray(Bytes.fromBigInt(bigInt));
}

export function createEventID(event: ethereum.Event): string {
  return event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
}

// Constants for date calculations
const SECONDS_PER_DAY: i32 = 86400;
const DAYS_PER_YEAR: i32 = 365;
const DAYS_PER_LEAP_YEAR: i32 = 366;

// Days in each month (non-leap year)
const DAYS_IN_MONTH: i32[] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

function isLeapYear(year: i32): boolean {
  return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
}

function getDaysInMonth(year: i32, month: i32): i32 {
  if (month == 2 && isLeapYear(year)) {
    return 29;
  }
  return DAYS_IN_MONTH[month - 1];
}

function getDaysInYear(year: i32): i32 {
  return isLeapYear(year) ? DAYS_PER_LEAP_YEAR : DAYS_PER_YEAR;
}

/**
 * Calculate year and month from Unix timestamp
 * Returns [year, month] where month is 1-12
 */
export function getYearAndMonth(timestamp: BigInt): i32[] {
  const totalDays = timestamp.div(BigInt.fromI32(SECONDS_PER_DAY)).toI32();

  // Start from Unix epoch (1970-01-01)
  let year: i32 = 1970;
  let remainingDays = totalDays;

  // Calculate year
  while (remainingDays >= getDaysInYear(year)) {
    remainingDays -= getDaysInYear(year);
    year++;
  }

  // Calculate month
  let month: i32 = 1;
  while (remainingDays >= getDaysInMonth(year, month)) {
    remainingDays -= getDaysInMonth(year, month);
    month++;
  }

  return [year, month];
}

/**
 * Get the Unix timestamp for the start of a given month
 */
export function getMonthStartTimestamp(year: i32, month: i32): BigInt {
  let days: i32 = 0;

  // Add days for years since 1970
  for (let y: i32 = 1970; y < year; y++) {
    days += getDaysInYear(y);
  }

  // Add days for months in current year
  for (let m: i32 = 1; m < month; m++) {
    days += getDaysInMonth(year, m);
  }

  return BigInt.fromI32(days).times(BigInt.fromI32(SECONDS_PER_DAY));
}

/**
 * Create a month ID from year and month (e.g., "2026-01")
 */
export function createMonthId(year: i32, month: i32): Bytes {
  const monthStr = month < 10 ? "0" + month.toString() : month.toString();
  return Bytes.fromUTF8(year.toString() + "-" + monthStr);
}
