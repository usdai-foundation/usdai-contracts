import { Address, BigInt, Bytes, log } from "@graphprotocol/graph-ts";

import {
  RedeemRequest as RedeemRequestEvent,
  RedemptionProcessed as RedemptionProcessedEvent,
  Transfer as TransferEvent,
  StakedUSDai,
} from "../generated/StakedUSDai/StakedUSDai";
import {
  Redemption,
  RedemptionProcessed,
  RedemptionRequest,
  RedemptionSharePriceSnapshot,
  SUSDaiStats,
  SUSDaiDayData,
} from "../generated/schema";
import { getDayStartTimestamp, getDayDateString, createDayId } from "./utils";
import { bytesFromBigInt } from "./utils/misc";

const SUSDAI_STATS_ID = Bytes.fromUTF8("susdai-stats");

function eventId(txHash: Bytes, logIndex: i32): Bytes {
  return txHash.concatI32(logIndex);
}

// Calls StakedUSDai.redemptionSharePrice() at the event's block and writes a snapshot
// entity keyed by (txHash, logIndex). If the eth_call reverts (e.g. very early blocks
// before the function was deployed), the snapshot is skipped and the data-app
// query-time logic falls back to the most recent prior snapshot.
function writeSharePriceSnapshot(
  contractAddress: Address,
  txHash: Bytes,
  logIndex: i32,
  blockNumber: BigInt,
  timestamp: BigInt,
): void {
  const contract = StakedUSDai.bind(contractAddress);
  const priceResult = contract.try_redemptionSharePrice();
  if (priceResult.reverted) return;

  const snapshot = new RedemptionSharePriceSnapshot(eventId(txHash, logIndex));
  snapshot.blockNumber = blockNumber;
  snapshot.timestamp = timestamp;
  snapshot.redemptionSharePrice = priceResult.value;
  snapshot.save();
}

export function handleRedeemRequest(event: RedeemRequestEvent): void {
  const logIndex = event.logIndex.toI32();
  const id = eventId(event.transaction.hash, logIndex);

  const entity = new RedemptionRequest(id);
  entity.redemptionId = event.params.requestId;
  entity.controller = event.params.controller;
  entity.owner = event.params.owner;
  entity.sender = event.params.sender;
  entity.shares = event.params.shares;
  entity.blockNumber = event.block.number;
  entity.timestamp = event.block.timestamp;
  entity.transactionHash = event.transaction.hash;
  entity.save();

  const redemptionId = bytesFromBigInt(event.params.requestId);
  const redemption = new Redemption(redemptionId);
  redemption.redemptionId = event.params.requestId;
  redemption.controller = event.params.controller;
  redemption.owner = event.params.owner;
  redemption.sender = event.params.sender;
  redemption.requestedShares = event.params.shares;
  redemption.pendingShares = event.params.shares;
  redemption.fulfilledShares = BigInt.fromI32(0);
  redemption.fulfilledAmount = BigInt.fromI32(0);
  redemption.active = true;
  redemption.requestedAtBlock = event.block.number;
  redemption.requestedAtTimestamp = event.block.timestamp;
  redemption.lastUpdatedBlock = event.block.number;
  redemption.lastUpdatedTimestamp = event.block.timestamp;
  redemption.requestTxHash = event.transaction.hash;
  redemption.save();

  writeSharePriceSnapshot(
    event.address,
    event.transaction.hash,
    logIndex,
    event.block.number,
    event.block.timestamp,
  );
}

export function handleRedemptionProcessed(event: RedemptionProcessedEvent): void {
  const logIndex = event.logIndex.toI32();
  const id = eventId(event.transaction.hash, logIndex);

  const entity = new RedemptionProcessed(id);
  entity.redemptionId = event.params.redemptionId;
  entity.controller = event.params.controller;
  entity.fulfilledShares = event.params.fulfilledShares;
  entity.amount = event.params.amount;
  entity.pendingShares = event.params.pendingShares;
  entity.blockNumber = event.block.number;
  entity.timestamp = event.block.timestamp;
  entity.transactionHash = event.transaction.hash;
  entity.save();

  const redemptionId = bytesFromBigInt(event.params.redemptionId);
  const redemption = Redemption.load(redemptionId);
  if (redemption == null) {
    log.warning("Redemption not found for redemptionId: {}", [event.params.redemptionId.toString()]);
    writeSharePriceSnapshot(
      event.address,
      event.transaction.hash,
      logIndex,
      event.block.number,
      event.block.timestamp,
    );
    return;
  }

  let newPendingShares = redemption.pendingShares.minus(event.params.fulfilledShares);
  if (newPendingShares.lt(BigInt.fromI32(0))) {
    log.warning("Pending shares would go negative for redemptionId: {}", [event.params.redemptionId.toString()]);
    newPendingShares = BigInt.fromI32(0);
  }

  redemption.pendingShares = newPendingShares;
  redemption.fulfilledShares = redemption.fulfilledShares.plus(event.params.fulfilledShares);
  redemption.fulfilledAmount = redemption.fulfilledAmount.plus(event.params.amount);
  redemption.active = redemption.pendingShares.gt(BigInt.fromI32(0));
  redemption.lastUpdatedBlock = event.block.number;
  redemption.lastUpdatedTimestamp = event.block.timestamp;
  redemption.save();

  writeSharePriceSnapshot(
    event.address,
    event.transaction.hash,
    logIndex,
    event.block.number,
    event.block.timestamp,
  );
}

export function handleSUSDaiTransfer(event: TransferEvent): void {
  let stats = SUSDaiStats.load(SUSDAI_STATS_ID);

  if (stats == null) {
    stats = new SUSDaiStats(SUSDAI_STATS_ID);
    stats.totalVolume = BigInt.fromI32(0);
    stats.transferCount = BigInt.fromI32(0);
  }

  stats.totalVolume = stats.totalVolume.plus(event.params.value);
  stats.transferCount = stats.transferCount.plus(BigInt.fromI32(1));
  stats.save();

  const dayId = createDayId(event.block.timestamp);
  let dayData = SUSDaiDayData.load(dayId);
  if (dayData == null) {
    dayData = new SUSDaiDayData(dayId);
    dayData.date = getDayDateString(event.block.timestamp);
    dayData.timestamp = getDayStartTimestamp(event.block.timestamp);
    dayData.volume = BigInt.fromI32(0);
    dayData.transferCount = BigInt.fromI32(0);
  }
  dayData.volume = dayData.volume.plus(event.params.value);
  dayData.transferCount = dayData.transferCount.plus(BigInt.fromI32(1));
  dayData.save();
}
