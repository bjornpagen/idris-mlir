#!/bin/sh
# One golden test, which the runner (tests/Runner.idr) runs in a process of
# its own, as many at once as it has threads:
#
#     tests/runner/one.sh RESULTS COMPILER TEST
#
# TEST's run script gets COMPILER as $1; its stdout, carriage returns
# removed, is TEST/output, which must be TEST/expected. The verdict, and on
# a failure both texts, go to stdout in one piece; TEST is appended to
# RESULTS/passed or RESULTS/failed. The run script bounds itself
# (tests/testutils.sh), and its output is cut there, so this ends.
results=$1
compiler=$2
test=$3
(cd "$test" && sh ./run "$compiler" | tr -d '\r' > output)

# The expectation: a target-specific expected.<name> where one exists,
# named as a `targets` file names this host (its architecture, x86-64 or
# aarch64, or its operating system, macos or linux), else `expected`. A
# test whose output is the target's own (a page size, the symbols a
# runtime needs) then holds on each target, with one expectation per
# target, instead of a skip or a loose check.
expected=$test/expected
for expected_name in ${IDRIS_MLIR_HOST_NAMES:?run the tests through make}; do
  if [ -f "$test/expected.$expected_name" ]; then
    expected=$test/expected.$expected_name
    break
  fi
done

report=$results/report.$$
if [ -f "$expected" ] && cmp -s "$expected" "$test/output"; then
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
    cat "$test/output"
    printf '\n'
  } > "$report"
  list=failed
fi
cat "$report"
rm -f "$report"
printf '%s\n' "$test" >> "$results/$list"
