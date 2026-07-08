#!/usr/bin/env bash
set -euo pipefail

CONTRACT_SIZE_LIMIT=24576

src_contract_names() {
  grep -RhE '^(abstract )?contract ' src/ \
    | sed -E 's/^(abstract )?contract ([A-Za-z0-9_]+).*/\2/' \
    | sort -u
}

filter_sizes() {
  local names
  names=$(src_contract_names | jq -R . | jq -s .)
  jq --argjson names "$names" 'with_entries(select(.key as $k | $names | index($k)))'
}

capture_sizes() {
  forge build --sizes --json 2>/dev/null | filter_sizes
}

compare_sizes() {
  local head="$1"
  local base="$2"

  jq -s --argjson limit "$CONTRACT_SIZE_LIMIT" '
    def fmt(n): "\(n) B";
    def delta(curr; base):
      if curr == base then "±0 B"
      elif curr > base then "+\(curr - base) B"
      else "\(curr - base) B"
      end;

    ((.[0] | keys) + (.[1] | keys) | unique | sort) as $keys
    | [
        $keys[] as $k
        | {
            contract: $k,
            head_runtime: (.[0][$k].runtime_size // null),
            base_runtime: (.[1][$k].runtime_size // null),
            head_init: (.[0][$k].init_size // null),
            base_init: (.[1][$k].init_size // null)
          }
        | .runtime_delta = (
            if .head_runtime == null or .base_runtime == null then null
            else .head_runtime - .base_runtime
            end
          )
        | .init_delta = (
            if .head_init == null or .base_init == null then null
            else .head_init - .base_init
            end
          )
        | select(
            .runtime_delta != 0
            or .init_delta != 0
            or .head_runtime == null
            or .base_runtime == null
            or (.head_runtime != null and .head_runtime > $limit)
          )
      ]
    | if length == 0 then
        "No contract size changes."
      else
        "| Contract | Head Runtime | Base Runtime | Δ Runtime | Head Initcode | Base Initcode | Δ Initcode |",
        "|---|---:|---:|---:|---:|---:|---:|",
        (
          .[]
          | "| \(.contract)"
            + " | \(if .head_runtime == null then "—" else fmt(.head_runtime) end)"
            + " | \(if .base_runtime == null then "—" else fmt(.base_runtime) end)"
            + " | \(if .runtime_delta == null then "—" else delta(.head_runtime; .base_runtime) end)"
            + " | \(if .head_init == null then "—" else fmt(.head_init) end)"
            + " | \(if .base_init == null then "—" else fmt(.base_init) end)"
            + " | \(if .init_delta == null then "—" else delta(.head_init; .base_init) end) |"
        )
      end
  ' "$head" "$base" -r
}

case "${1:-}" in
  names)
    src_contract_names
    ;;
  capture)
    capture_sizes
    ;;
  filter)
    filter_sizes
    ;;
  compare)
    if [[ $# -ne 3 ]]; then
      echo "Usage: $0 compare <head.json> <base.json>" >&2
      exit 1
    fi
    compare_sizes "$2" "$3"
    ;;
  *)
    echo "Usage: $0 {names|capture|filter|compare}" >&2
    exit 1
    ;;
esac
