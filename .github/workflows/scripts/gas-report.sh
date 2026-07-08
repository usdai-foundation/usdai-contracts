#!/usr/bin/env bash
set -euo pipefail

src_contract_names() {
  grep -RhE '^(abstract )?contract ' src/ \
    | sed -E 's/^(abstract )?contract ([A-Za-z0-9_]+).*/\2/' \
    | sort -u \
    | jq -R . \
    | jq -s .
}

normalize_report() {
  local names
  names=$(src_contract_names)
  jq -s --argjson names "$names" '
    [.[].[] | select(.contract | split(":")[1] as $name | $names | index($name))]
    | group_by(.contract)
    | map({
        contract: (.[0].contract | split(":")[1]),
        functions: (
          [.[].functions | to_entries[]]
          | group_by(.key)
          | map({
              key: .[0].key,
              value: {
                max: (map(.value.max) | max),
                calls: (map(.value.calls) | add)
              }
            })
          | from_entries
        )
      })
    | map({(.contract): .functions})
    | add
  '
}

capture_report() {
  forge test --gas-report --json 2>/dev/null | normalize_report
}

compare_reports() {
  local head="$1"
  local base="$2"

  jq -s '
    def fmt(n): if n == null then "—" else "\(n)" end;
    def delta(curr; base):
      if curr == null or base == null then "—"
      elif curr == base then "±0"
      elif curr > base then "+\(curr - base)"
      else "\(curr - base)"
      end;

    (.[0] // {}) as $head
    | (.[1] // {}) as $base
    | ([($head | keys), ($base | keys)] | add | unique | sort) as $contracts
    | [
        $contracts[] as $contract
        | ([
            ($head[$contract] // {} | keys[]),
            ($base[$contract] // {} | keys[])
          ] | unique | sort)[] as $fn
        | {
            contract: $contract,
            function: $fn,
            head_max: ($head[$contract][$fn].max // null),
            base_max: ($base[$contract][$fn].max // null),
            head_calls: ($head[$contract][$fn].calls // null),
            base_calls: ($base[$contract][$fn].calls // null)
          }
        | .max_delta = (
            if .head_max == null or .base_max == null then null
            else .head_max - .base_max
            end
          )
        | select(.max_delta != 0 or .head_max == null or .base_max == null)
      ]
    | sort_by(-((.max_delta // 0) | if . < 0 then -. else . end))
    | if length == 0 then
        "No function max gas changes."
      else
        "| Contract | Function | Head Max | Base Max | Δ Max | Head Calls | Base Calls |",
        "|---|---|---:|---:|---:|---:|---:|",
        (
          .[]
          | "| \(.contract)"
            + " | `\(.function)`"
            + " | \(fmt(.head_max))"
            + " | \(fmt(.base_max))"
            + " | \(delta(.head_max; .base_max))"
            + " | \(fmt(.head_calls))"
            + " | \(fmt(.base_calls)) |"
        )
      end
  ' "$head" "$base" -r
}

case "${1:-}" in
  capture)
    capture_report
    ;;
  compare)
    if [[ $# -ne 3 ]]; then
      echo "Usage: $0 compare <head.json> <base.json>" >&2
      exit 1
    fi
    compare_reports "$2" "$3"
    ;;
  *)
    echo "Usage: $0 {capture|compare}" >&2
    exit 1
    ;;
esac
