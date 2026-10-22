# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# What the golden tests' scripts share: a scripted test's own `run`, and
# the script of each other kind (harness/kinds). Each starts with
#
#     . "$IDRIS_MLIR_ROOT/harness/testutils.sh"
#
# and gets the idris-mlir under test as $idris_mlir, tools/toolchain.sh's,
# which is also the $1 the runner passes (harness/one.sh). Each check
# prints one line, the same on every successful run, and more lines only when
# it fails, so `expected` holds the successful output and a failure shows as
# a difference. Expectations are read from the fixtures in place (headers,
# each case's files under cases/, mlir.expect), so each has one source of
# truth. Everything is built in a temporary directory, removed on exit. The
# Idris environment is the Makefile's.
#
# A program fixture may carry a mark, a file named for what it changes in
# its compilation; what a run reads and gives, and the marks of one run,
# are the files of a case (Programs.idr, which holds the one list of
# both). Any other file but the test's own and its modules fails the test:
#
#     heap-free       no op of the module that is lowered allocates a heap
#                     cell (Harness.idr, stageOptions)
#     covers          the program uses every run-time export of the prelude
#                     module the file names, as its module shows (Covers.idr)
#     mlir.expect     the properties the program's stages hold
#
# What the scripts share is the runner's (harness/*.idr, which Main.idr
# lists), called by its shell name from harness/lib/harness.sh, sourced
# below after the limits: the glue that starts each tool a check needs,
# with the work directory, a command bounded, and a RUN line's commands.

root=${IDRIS_MLIR_ROOT:?IDRIS_MLIR_ROOT must name the repository}

# No test can hang. Every command a test runs is bounded (`bounded`, in
# lib/harness.sh, through which the runner starts each tool too) by
# step_limit seconds, and the whole run script by
# test_limit seconds: the first time this file is sourced, it runs the script
# again under `timeout` and, if the script is killed, prints that it timed
# out, which no expected output holds, so the test fails. A run script that
# does many compilations (the fuzzer) sets a larger
# test_limit before sourcing this file. A limit never passes a test, it
# only ends one. coreutils' timeout is $timeout_cmd (tools/host.sh).
. "$root/tools/host.sh"
if [ -z "$timeout_cmd" ]; then
  printf '%s\n' "test: $timeout_missing, so the test could hang"
  exit 1
fi
step_limit=${step_limit:-60}
test_limit=${test_limit:-300}
# The output is bounded too, at 256 KiB, since the runner reads all of it:
# a longer one is cut, and says so, which fails the test.
if [ -z "${IDRIS_MLIR_TEST_DEADLINE-}" ]; then
  deadline_output=$(mktemp "${TMPDIR:-/tmp}/idris-mlir-output.XXXXXX") || exit 1
  IDRIS_MLIR_TEST_DEADLINE=$test_limit "$timeout_cmd" -k 10 "$test_limit" sh "$0" "$@" > "$deadline_output"
  deadline_status=$?
  head -c 262144 "$deadline_output"
  [ "$(wc -c < "$deadline_output")" -le 262144 ] || printf '\n%s\n' "test: output cut at 256 KiB"
  rm -f "$deadline_output"
  case $deadline_status in
    124 | 137) printf '%s\n' "test: timed out after ${test_limit}s" ;;
  esac
  exit "$deadline_status"
fi

. "$root/harness/lib/harness.sh"
