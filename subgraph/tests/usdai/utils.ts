import { Address, BigInt, ethereum } from "@graphprotocol/graph-ts";
import { newMockEvent } from "matchstick-as";
import { Transfer as TransferEvent } from "../../generated/USDai/USDai";

// Test addresses
export const ALICE = Address.fromString("0x1111111111111111111111111111111111111111");
export const BOB = Address.fromString("0x2222222222222222222222222222222222222222");
export const CHARLIE = Address.fromString("0x3333333333333333333333333333333333333333");
export const ZERO_ADDRESS = Address.fromString("0x0000000000000000000000000000000000000000");

// Known Unix timestamps for testing
export class TestTimestamps {
  // January 2024
  static JAN_2024_START: BigInt = BigInt.fromI32(1704067200); // 2024-01-01 00:00:00 UTC
  static JAN_2024_MID: BigInt = BigInt.fromI32(1705312800); // 2024-01-15 10:00:00 UTC
  static JAN_2024_END: BigInt = BigInt.fromI32(1706745599); // 2024-01-31 23:59:59 UTC

  // February 2024 (leap year)
  static FEB_2024_START: BigInt = BigInt.fromI32(1706745600); // 2024-02-01 00:00:00 UTC
  static FEB_2024_LEAP_DAY: BigInt = BigInt.fromI32(1709208000); // 2024-02-29 12:00:00 UTC

  // March 2024
  static MAR_2024_START: BigInt = BigInt.fromI32(1709251200); // 2024-03-01 00:00:00 UTC

  // December 2023
  static DEC_2023_MID: BigInt = BigInt.fromI32(1702396800); // 2023-12-12 16:00:00 UTC

  // December 2024
  static DEC_2024_END: BigInt = BigInt.fromI32(1735689599); // 2024-12-31 23:59:59 UTC

  // January 2025
  static JAN_2025_START: BigInt = BigInt.fromI32(1735689600); // 2025-01-01 00:00:00 UTC

  // Unix epoch
  static EPOCH: BigInt = BigInt.fromI32(0); // 1970-01-01 00:00:00 UTC

  // February 2023 (non-leap year)
  static FEB_2023_END: BigInt = BigInt.fromI32(1677628799); // 2023-02-28 23:59:59 UTC
  static MAR_2023_START: BigInt = BigInt.fromI32(1677628800); // 2023-03-01 00:00:00 UTC
}

// Common transfer amounts (in wei - USDai has 18 decimals)
export class TransferAmounts {
  static ONE_WEI: BigInt = BigInt.fromI32(1);
  static ONE: BigInt = BigInt.fromI32(10).pow(18); // 1 USDai = 10^18 wei
  static ONE_HUNDRED: BigInt = TransferAmounts.ONE.times(BigInt.fromI32(100));
  static ONE_THOUSAND: BigInt = TransferAmounts.ONE.times(BigInt.fromI32(1000));
  static ONE_MILLION: BigInt = TransferAmounts.ONE.times(BigInt.fromI32(1000000));
  static ZERO: BigInt = BigInt.fromI32(0);
}

/**
 * Creates a mock Transfer event for testing
 */
export function createTransferEvent(
  from: Address,
  to: Address,
  value: BigInt,
  timestamp: BigInt
): TransferEvent {
  const mockEvent = newMockEvent();

  // Set timestamp on block
  mockEvent.block.timestamp = timestamp;

  // Create Transfer event
  const transferEvent = new TransferEvent(
    mockEvent.address,
    mockEvent.logIndex,
    mockEvent.transactionLogIndex,
    mockEvent.logType,
    mockEvent.block,
    mockEvent.transaction,
    mockEvent.parameters,
    mockEvent.receipt
  );

  // Set up parameters
  transferEvent.parameters = new Array();

  const fromParam = new ethereum.EventParam("from", ethereum.Value.fromAddress(from));
  const toParam = new ethereum.EventParam("to", ethereum.Value.fromAddress(to));
  const valueParam = new ethereum.EventParam("value", ethereum.Value.fromUnsignedBigInt(value));

  transferEvent.parameters.push(fromParam);
  transferEvent.parameters.push(toParam);
  transferEvent.parameters.push(valueParam);

  return transferEvent;
}
