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
host_arch=${IDRIS_MLIR_HOST_ARCH:-$(uname -m)}
case $host_arch in
  x86_64 | amd64) host_arch=x86-64 ;;
  arm64 | aarch64) host_arch=aarch64 ;;
esac
host_os=$(uname -s)
case $host_os in
  Darwin) host_os=macos ;;
  Linux) host_os=linux ;;
  *) host_os=$(printf '%s' "$host_os" | tr '[:upper:]' '[:lower:]') ;;
esac
for expected_name in "$host_arch" "$host_os"; do
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
