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
report=$results/report.$$
if [ -f "$test/expected" ] && cmp -s "$test/expected" "$test/output"; then
  printf '%s: success\n' "$test" > "$report"
  list=passed
else
  {
    printf '%s: FAILURE\n' "$test"
    if [ -f "$test/expected" ]; then
      printf 'Expected:\n'
      cat "$test/expected"
    else
      printf '%s/expected: missing\n' "$test"
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
