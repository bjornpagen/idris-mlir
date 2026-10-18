#!/bin/sh
# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# One golden test, which the runner (tests/Runner.idr) runs in a process of
# its own, as many at once as it has threads:
#
#     tests/runner/one.sh RESULTS COMPILER TEST
#
# TEST is a directory, or `<directory>@<parameter>`, one run of a
# directory the runner runs once per parameter (tests/Main.idr), split
# here at its first `@`. The directory's run script gets COMPILER as $1
# and the parameter, if any, as $2; its stdout, carriage returns removed,
# is the directory's `output`, or `output/<parameter>`, which must be its
# `expected`. The verdict, and on a failure both texts, go to stdout in one
# piece; TEST is appended to RESULTS/passed or RESULTS/failed. The run
# script bounds itself (tests/testutils.sh), and its output is cut there,
# so this ends.
results=$1
compiler=$2
test=$3
case $test in
  *@*)
    directory=${test%%@*}
    parameter=${test#*@}
    mkdir -p "$directory/output"
    output=$directory/output/$parameter ;;
  *)
    directory=$test
    parameter=
    output=$directory/output ;;
esac
(cd "$directory" && sh ./run "$compiler" ${parameter:+"$parameter"} | tr -d '\r') > "$output"

# The expectation: a target-specific expected.<name> where one exists,
# named as a `targets` file names this host (its architecture, x86-64 or
# aarch64, or its operating system, macos or linux), else `expected`. A
# test whose output is the target's own (a page size, the symbols a
# runtime needs) then holds on each target, with one expectation per
# target, instead of a skip or a loose check.
expected=$directory/expected
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
      printf 'Expected:\n'
      cat "$expected"
    else
      printf '%s: missing\n' "$expected"
    fi
    printf 'Given:\n'
    cat "$output"
    printf '\n'
  } > "$report"
  list=failed
fi
cat "$report"
rm -f "$report"
printf '%s\n' "$test" >> "$results/$list"
