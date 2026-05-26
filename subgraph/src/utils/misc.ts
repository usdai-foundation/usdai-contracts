import { BigInt, Bytes, ethereum } from "@graphprotocol/graph-ts";

export function bytesFromBigInt(bigInt: BigInt): Bytes {
  return Bytes.fromByteArray(Bytes.fromBigInt(bigInt));
}

export function createEventID(event: ethereum.Event): string {
  return event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
}

const SECONDS_PER_DAY: i32 = 86400;
const DAYS_PER_YEAR: i32 = 365;
const DAYS_PER_LEAP_YEAR: i32 = 366;

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

export function getDayStartTimestamp(timestamp: BigInt): BigInt {
  const day = timestamp.div(BigInt.fromI32(SECONDS_PER_DAY));
  return day.times(BigInt.fromI32(SECONDS_PER_DAY));
}

export function getDayDateString(timestamp: BigInt): string {
  const totalDays = timestamp.div(BigInt.fromI32(SECONDS_PER_DAY)).toI32();
  let year: i32 = 1970;
  let remainingDays = totalDays;
  while (remainingDays >= getDaysInYear(year)) {
    remainingDays -= getDaysInYear(year);
    year++;
  }
  let month: i32 = 1;
  while (remainingDays >= getDaysInMonth(year, month)) {
    remainingDays -= getDaysInMonth(year, month);
    month++;
  }
  const day: i32 = remainingDays + 1; // 1-indexed day-of-month
  const mm = month < 10 ? "0" + month.toString() : month.toString();
  const dd = day < 10 ? "0" + day.toString() : day.toString();
  return year.toString() + "-" + mm + "-" + dd;
}

export function createDayId(timestamp: BigInt): Bytes {
  return Bytes.fromUTF8(getDayDateString(timestamp));
}
