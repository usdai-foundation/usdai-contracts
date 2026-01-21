import { BigInt, Bytes } from "@graphprotocol/graph-ts";
import { Transfer as TransferEvent } from "../generated/USDai/USDai";
import { USDaiStats, USDaiMonthData } from "../generated/schema";
import { getYearAndMonth, getMonthStartTimestamp, createMonthId } from "./utils";

const STATS_ID = Bytes.fromUTF8("stats");

export function handleTransfer(event: TransferEvent): void {
  // Update cumulative stats
  let stats = USDaiStats.load(STATS_ID);

  if (stats == null) {
    stats = new USDaiStats(STATS_ID);
    stats.totalVolume = BigInt.fromI32(0);
    stats.transferCount = BigInt.fromI32(0);
  }

  stats.totalVolume = stats.totalVolume.plus(event.params.value);
  stats.transferCount = stats.transferCount.plus(BigInt.fromI32(1));
  stats.save();

  // Update monthly aggregation
  const yearMonth = getYearAndMonth(event.block.timestamp);
  const year = yearMonth[0];
  const month = yearMonth[1];
  const monthId = createMonthId(year, month);

  let monthData = USDaiMonthData.load(monthId);

  if (monthData == null) {
    monthData = new USDaiMonthData(monthId);
    monthData.year = year;
    monthData.month = month;
    monthData.timestamp = getMonthStartTimestamp(year, month);
    monthData.volume = BigInt.fromI32(0);
    monthData.transferCount = BigInt.fromI32(0);
  }

  monthData.volume = monthData.volume.plus(event.params.value);
  monthData.transferCount = monthData.transferCount.plus(BigInt.fromI32(1));
  monthData.save();
}
