#!/bin/bash
# Usage: run.sh REPS WORKLOAD...
# Runs ./b_mi, ./b_mi with tuned options, and ./b_sn REPS times per workload,
# and prints the median time, all times sorted, and the median peak RSS.
set -euo pipefail
reps=$1; shift
for w in "$@"; do
  for cfg in mi mitune sn; do
    case $cfg in
      mi) cmd="./b_mi";;
      sn) cmd="./b_sn";;
      mitune) cmd="env MIMALLOC_PAGE_RECLAIM_ON_FREE=1 MIMALLOC_PAGE_FULL_RETAIN=-1 ./b_mi";;
    esac
    out=$(for _ in $(seq "$reps"); do $cmd "$w"; done)
    ts=$(echo "$out" | awk '{print $3}' | sort -n | tr '\n' ' ')
    rs=$(echo "$out" | awk '{print $6}' | sort -n | tr '\n' ' ')
    mid=$(( (reps + 1) / 2 ))
    printf "%-7s %-11s median %s s  [%s]  maxrss %s KiB\n" \
      "$cfg" "$w" "$(echo $ts | cut -d' ' -f$mid)" "$ts" "$(echo $rs | cut -d' ' -f$mid)"
  done
done
