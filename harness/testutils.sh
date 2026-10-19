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
# are the files of a case (case_fields, e2e_case in e2e.sh). Any other file
# but the test's own and its modules fails the test (fixture_files_known,
# in e2e.sh, which holds the one list):
#
#     heap-free       no op of the lowered module allocates a heap cell
#                     (heap.sh)
#     default-stack   the program runs on the default stack instead of the
#                     1 MiB one; the file says why (e2e.sh)
#     covers          the program uses every run-time export of the prelude
#                     module the file names, as its Core shows (prelude.sh)
#
# The helpers are in harness/lib, one file per concern, sourced below after
# the limits, each after what it uses:
#
#     harness.sh       the work directory, bounded commands, output, fixtures,
#                      the packages a fixture names
#     timing.sh        the record of every compilation's wall time
#     rules.sh         the rules a refusal names, from their generated list
#     compile.sh       compiling a program, and the artifacts it leaves
#     run.sh           running a compiled program
#     heap.sh          the C library calls an e2e program's objects may make
#     mlir.sh          the modules a compilation dumps, step by step
#     expect.sh        properties of a module by name (idr-expect), mlir.expect
#     prelude.sh       a prelude module whose every export a program uses
#     e2e.sh           the end-to-end programs, each compiled once and run on
#                      each case, the generated semantics tests, and a refused
#                      program's neighbour
#     properties.sh    what holds of every compilation, off its dumps, as one line
#     profile.sh       the profile's accept and reject fixtures
#     determinism.sh   compilations at 1, 3, 5 and 13 threads and in a second
#                      process, and one thread against the pool, byte for byte
#     lit.sh           the dialect tests' RUN lines
#     differential.sh  %differential: two modules' programs agree on every input
#     planted.sh       a repository rule on its planted witness and near miss
#     fuzz.sh          the fuzzer
#     idris-lex.sh     Idris source, code told from comments and strings
#     cpp-lex.sh       C and C++ source, code told from comments and literals
#     bench.sh         the benchmarks, built and run on small inputs

root=${IDRIS_MLIR_ROOT:?IDRIS_MLIR_ROOT must name the repository}

# No test can hang. Every command a test runs is bounded (`bounded`, in
# lib/harness.sh) by step_limit seconds, and the whole run script by
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
# No test can exhaust the machine's memory either. A program this compiler
# built holds no more heap than its one region, which IDRIS_RT_HEAP sizes
# (runtime/Alloc/Cells.cpp), and no more stack than its reserved one, so
# every process a test starts gets heap_limit bytes of heap: the programs,
# a differential's among them, and the folds idris-mlir runs. As the time
# limit ends a run that hangs, the heap's end ends one that runs away, with
# `out of memory`, and as many tests as the runner runs at once hold a
# gibibyte each at most.
heap_limit=${heap_limit:-1073741824}
IDRIS_RT_HEAP=$heap_limit
export IDRIS_RT_HEAP
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

for lib_file in harness timing rules compile run heap mlir expect prelude properties e2e \
                profile determinism lit differential planted fuzz idris-lex cpp-lex bench; do
  . "$root/harness/lib/$lib_file.sh"
done
unset lib_file
