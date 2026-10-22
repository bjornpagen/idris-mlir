#!/bin/sh
# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# The runs of the golden tests, which the runner (harness/Main.idr) plans
# and tallies but does not make: it builds under both hosts, and idris-mlir
# refuses process creation, so creating the processes is this glue's.
#
#     harness/runs.sh RUNNER COMPILER [--suite NAME] [--list] [--threads N]
#                     [--only NAMES] [--except NAMES] [--only-file PATH]
#
# From tests/, as make runs it: the runner writes the plan of the runs the
# options select into a directory of its own (Runner.idr names its files),
# then each pool in turn runs through xargs, as many runs at once as the
# plan's threads, each in a process of its own (harness/one.sh), and the
# runner tallies their verdicts; its status is this script's. `--list`
# prints the runs the options select, and runs none.
runner=$1
compiler=$2
shift 2
results=${IDRIS_MLIR_ROOT:?run the tests through make}/harness/build/results.$$
rm -rf "$results" && mkdir -p "$results" || exit 1
trap 'rm -rf "$results"' EXIT
"$runner" --plan "$results" "$compiler" "$@" || exit
# A listing writes no plan.
[ -f "$results/selected" ] || exit 0
threads=$(cat "$results/threads")
n=1
while [ -f "$results/pool.$n.runs" ]; do
  cat "$results/pool.$n.banner"
  xargs -P "$threads" -n 2 sh "$IDRIS_MLIR_ROOT/harness/one.sh" "$runner" "$results" "$compiler" < "$results/pool.$n.runs"
  n=$((n + 1))
done
"$runner" --tally "$results"
