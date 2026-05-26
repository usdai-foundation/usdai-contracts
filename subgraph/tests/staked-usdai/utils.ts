import { Address, BigInt, ethereum } from "@graphprotocol/graph-ts";
import { newMockEvent } from "matchstick-as";

import {
  RedeemRequest as RedeemRequestEvent,
  RedemptionProcessed as RedemptionProcessedEvent,
  Transfer as TransferEvent,
} from "../../generated/StakedUSDai/StakedUSDai";

// Address of the deployed StakedUSDai contract on Arbitrum mainnet. Used for
// createMockedFunction() so eth_calls in the mapping resolve.
export const STAKED_USDAI_ADDRESS = Address.fromString(
  "0x0B2b2B2076d95dda7817e785989fE353fe955ef9"
);

export function createRedeemRequestEvent(
  controller: Address,
  owner: Address,
  requestId: BigInt,
  sender: Address,
  shares: BigInt,
  timestamp: BigInt,
  blockNumber: BigInt
): RedeemRequestEvent {
  const mockEvent = newMockEvent();
  mockEvent.block.timestamp = timestamp;
  mockEvent.block.number = blockNumber;

  const event = new RedeemRequestEvent(
    STAKED_USDAI_ADDRESS,
    mockEvent.logIndex,
    mockEvent.transactionLogIndex,
    mockEvent.logType,
    mockEvent.block,
    mockEvent.transaction,
    mockEvent.parameters,
    mockEvent.receipt
  );

  event.parameters = new Array();
  event.parameters.push(new ethereum.EventParam("controller", ethereum.Value.fromAddress(controller)));
  event.parameters.push(new ethereum.EventParam("owner", ethereum.Value.fromAddress(owner)));
  event.parameters.push(new ethereum.EventParam("requestId", ethereum.Value.fromUnsignedBigInt(requestId)));
  event.parameters.push(new ethereum.EventParam("sender", ethereum.Value.fromAddress(sender)));
  event.parameters.push(new ethereum.EventParam("shares", ethereum.Value.fromUnsignedBigInt(shares)));

  return event;
}

export function createRedemptionProcessedEvent(
  redemptionId: BigInt,
  controller: Address,
  fulfilledShares: BigInt,
  amount: BigInt,
  pendingShares: BigInt,
  timestamp: BigInt,
  blockNumber: BigInt
): RedemptionProcessedEvent {
  const mockEvent = newMockEvent();
  mockEvent.block.timestamp = timestamp;
  mockEvent.block.number = blockNumber;

  const event = new RedemptionProcessedEvent(
    STAKED_USDAI_ADDRESS,
    mockEvent.logIndex,
    mockEvent.transactionLogIndex,
    mockEvent.logType,
    mockEvent.block,
    mockEvent.transaction,
    mockEvent.parameters,
    mockEvent.receipt
  );

  event.parameters = new Array();
  event.parameters.push(new ethereum.EventParam("redemptionId", ethereum.Value.fromUnsignedBigInt(redemptionId)));
  event.parameters.push(new ethereum.EventParam("controller", ethereum.Value.fromAddress(controller)));
  event.parameters.push(new ethereum.EventParam("fulfilledShares", ethereum.Value.fromUnsignedBigInt(fulfilledShares)));
  event.parameters.push(new ethereum.EventParam("amount", ethereum.Value.fromUnsignedBigInt(amount)));
  event.parameters.push(new ethereum.EventParam("pendingShares", ethereum.Value.fromUnsignedBigInt(pendingShares)));

  return event;
}

export function createTransferEvent(
  from: Address,
  to: Address,
  value: BigInt,
  timestamp: BigInt
): TransferEvent {
  const mockEvent = newMockEvent();
  mockEvent.block.timestamp = timestamp;

  const event = new TransferEvent(
    STAKED_USDAI_ADDRESS,
    mockEvent.logIndex,
    mockEvent.transactionLogIndex,
    mockEvent.logType,
    mockEvent.block,
    mockEvent.transaction,
    mockEvent.parameters,
    mockEvent.receipt
  );

  event.parameters = new Array();
  event.parameters.push(new ethereum.EventParam("from", ethereum.Value.fromAddress(from)));
  event.parameters.push(new ethereum.EventParam("to", ethereum.Value.fromAddress(to)));
  event.parameters.push(new ethereum.EventParam("value", ethereum.Value.fromUnsignedBigInt(value)));

  return event;
}
