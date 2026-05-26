import { BigInt, Bytes } from "@graphprotocol/graph-ts";
import { Transfer as TransferEvent } from "../generated/USDai/USDai";
import { USDaiStats, USDaiDayData } from "../generated/schema";
import { getDayStartTimestamp, getDayDateString, createDayId } from "./utils";

const STATS_ID = Bytes.fromUTF8("stats");

export function handleTransfer(event: TransferEvent): void {
  let stats = USDaiStats.load(STATS_ID);

  if (stats == null) {
    stats = new USDaiStats(STATS_ID);
    stats.totalVolume = BigInt.fromI32(0);
    stats.transferCount = BigInt.fromI32(0);
  }

  stats.totalVolume = stats.totalVolume.plus(event.params.value);
  stats.transferCount = stats.transferCount.plus(BigInt.fromI32(1));
  stats.save();

  const dayId = createDayId(event.block.timestamp);
  let dayData = USDaiDayData.load(dayId);
  if (dayData == null) {
    dayData = new USDaiDayData(dayId);
    dayData.date = getDayDateString(event.block.timestamp);
    dayData.timestamp = getDayStartTimestamp(event.block.timestamp);
    dayData.volume = BigInt.fromI32(0);
    dayData.transferCount = BigInt.fromI32(0);
  }
  dayData.volume = dayData.volume.plus(event.params.value);
  dayData.transferCount = dayData.transferCount.plus(BigInt.fromI32(1));
  dayData.save();
}
