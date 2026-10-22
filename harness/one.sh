#!/bin/sh
# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# One golden test, which the runner (harness/Runner.idr) runs in a process
# of its own, from tests/, as many at once as it has threads:
#
#     harness/one.sh RUNNER RESULTS COMPILER KIND TEST
#
# TEST is a test's directory, or `<directory>@<parameter>`, one run of a
# test the runner runs once per parameter (harness/Main.idr), split here at
# its first `@`. KIND is what the runner found the directory to hold: a
# `script` runs its own `run`; a `program`, a `reject` or a `fixture` runs
# the script of its kind, harness/kinds/<kind>. Either runs in the test's
# directory, with COMPILER as $1 and the parameter, if any, as $2; its
# stdout, carriage returns removed, is the run's output,
# harness/build/output/<TEST>. The runner holds it to its expectation and
# reports the verdict (`runtests --verdict`, Verdict.idr). The run bounds
# itself (harness/testutils.sh), and its output is cut there, so this
# ends.
runner=$1
results=$2
compiler=$3
kind=$4
test=$5
harness=${IDRIS_MLIR_ROOT:?run the tests through make}/harness
case $test in
  *@*)
    directory=${test%%@*}
    parameter=${test#*@} ;;
  *)
    directory=$test
    parameter= ;;
esac
case $kind in
  script) script=./run ;;
  *) script=$harness/kinds/$kind ;;
esac
mkdir -p "$harness/build/output"
output=$harness/build/output/$test
stderr=$results/stderr.$$
(cd "$directory" && sh "$script" "$compiler" ${parameter:+"$parameter"} 2> "$stderr" | tr -d '\r') > "$output"
"$runner" --verdict "$results" "$test" "$directory" "$kind" "$output" "$stderr"
rm -f "$stderr"
