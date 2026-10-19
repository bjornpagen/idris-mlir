#!/bin/sh
# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# One golden test, which the runner (harness/Runner.idr) runs in a process
# of its own, from tests/, as many at once as it has threads:
#
#     harness/one.sh RESULTS COMPILER KIND TEST
#
# TEST is a test's directory, or `<directory>@<parameter>`, one run of a
# test the runner runs once per parameter (harness/Main.idr), split here at
# its first `@`. KIND is what the runner found the directory to hold: a
# `script` runs its own `run`; a `program`, a `reject` or a `fixture` runs
# the script of its kind, harness/kinds/<kind>. Either runs in the test's
# directory, with COMPILER as $1 and the parameter, if any, as $2; its
# stdout, carriage returns removed, is the run's output,
# harness/build/output/<TEST>, which must be its expectation. The verdict,
# and on a failure the difference from the expectation (or the whole
# output, when there is none) and what the run wrote on stderr, go to
# stdout in one piece; TEST is appended to RESULTS/passed or
# RESULTS/failed. The run bounds itself (harness/testutils.sh), and its
# output is cut there, so this ends.
results=$1
compiler=$2
kind=$3
test=$4
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

# The expectation: a target-specific expected.<name> where one exists,
# named as a `targets` file names this host (its architecture, x86-64 or
# aarch64, or its operating system, macos or linux), else `expected`, else
# the kind's own, harness/kinds/<kind>.expected, for a kind that fixes what
# a good run prints (a fixture: every RUN line holds). A test whose output
# is the target's own (a page size, the symbols a runtime needs) then holds
# on each target, with one expectation per target, instead of a skip or a
# loose check.
expected=$directory/expected
[ -f "$expected" ] || [ ! -f "$harness/kinds/$kind.expected" ] || expected=$harness/kinds/$kind.expected
for expected_name in ${IDRIS_MLIR_HOST_NAMES:?run the tests through make}; do
  if [ -f "$directory/expected.$expected_name" ]; then
    expected=$directory/expected.$expected_name
    break
  fi
done

report=$results/report.$$
if [ -f "$expected" ] && cmp -s "$expected" "$output"; then
  printf '%s: success\n' "$test" > "$report"
  list=passed
else
  {
    printf '%s: FAILURE\n' "$test"
    if [ -f "$expected" ]; then
      printf -- '- %s, + %s:\n' "$expected" "$output"
      diff -u "$expected" "$output" | sed '1,2d'
    else
      printf '%s: missing; the output, %s, is:\n' "$expected" "$output"
      cat "$output"
    fi
    if [ -s "$stderr" ]; then
      printf 'stderr of %s:\n' "$test"
      head -n 40 "$stderr" | sed 's/^/  | /'
    fi
    printf '\n'
  } > "$report"
  list=failed
fi
cat "$report"
rm -f "$report" "$stderr"
printf '%s\n' "$test" >> "$results/$list"
