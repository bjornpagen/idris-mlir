# What the golden tests' run scripts share. A run
# script starts with
#
#     . "$IDRIS_MLIR_ROOT/tests/testutils.sh"
#
# and gets the idris-mlir under test as $1 (tests/Main.idr). Each check
# prints one line, the same on every successful run, and more lines only when
# it fails, so `expected` holds the successful output and a failure shows as
# a difference. Expectations are read from the fixtures in place (headers,
# stdin, expected-stdout, expected-exit, expected-crash, Oracle.idr and the
# *.check files), so each has one source of truth. Everything is built in a
# temporary directory, removed on exit. The Idris environment is the
# Makefile's.
#
# A fixture may carry a mark, a file named for what it changes:
#
#     heap-free       no op of the lowered module allocates a heap cell
#                     (heap.sh)
#     oracle-chez     Chez's stdout is the only oracle of stdout (e2e.sh)
#     no-chez         Chez is not run; the file says why (e2e.sh)
#     chez-differs    Chez knowingly prints something else: the file names a
#                     class of tests/lib/chez-divergences, and chez-stdout
#                     is what Chez prints (chez.sh)
#     libm-lines      the numbered output lines are libm results, which may
#                     differ from Chez's in the last place (chez.sh)
#     default-stack   the program runs on the default stack instead of the
#                     1 MiB one; the file says why (e2e.sh)
#     constant-stack  the program loops in constant stack on a long input:
#                     its stdin is the fixture's stdin as many times over as
#                     the file's first word says, so many iterations that a
#                     loop keeping one frame per iteration exhausts the 1 MiB
#                     stack it runs on; the file says what loops (e2e.sh)
#
# The helpers are in tests/lib, one file per concern, sourced below after
# the limits, each after what it uses:
#
#     harness.sh       the work directory, bounded commands, output, fixtures
#     timing.sh        the record of every compilation's wall time
#     compile.sh       compiling a program, and the artifacts it leaves
#     run.sh           running a compiled program
#     heap.sh          the C library calls an e2e program's object may make
#     mlir.sh          FileCheck, and the module an mlir.check reads
#     expect.sh        properties of a module by name (idr-expect), mlir.expect
#     oracle.sh        Oracle.idr, and the generated semantics tests
#     chez.sh          the stock Chez backend as an oracle, and its text of a
#                      Double read as this compiler's (chez-doubles.ss)
#     e2e.sh           the end-to-end programs, each compiled twice
#     properties.sh    what holds of every compilation, off its dumps
#     profile.sh       the profile's accept and reject fixtures
#     determinism.sh   two compilations, byte for byte
#     lit.sh           the dialect tests' RUN lines
#     fuzz.sh          the fuzzer
#     two-levels.sh    Idris's evaluator against the compiled program
#     idris-lex.sh     Idris source, code told from comments and strings
#     bench.sh         the benchmarks, built and run on small inputs
#     upstream.sh      clang bugs a unit of ours reproduces, compiled in place

idris_mlir=$1
root=${IDRIS_MLIR_ROOT:?IDRIS_MLIR_ROOT must name the repository}

# No test can hang. Every command a test runs is bounded (`bounded`, in
# lib/harness.sh) by step_limit seconds, and the whole run script by
# test_limit seconds: the first time this file is sourced, it runs the script
# again under `timeout` and, if the script is killed, prints that it timed
# out, which no expected output holds, so the test fails. A run script that
# does many compilations (fuzz, two levels) sets a larger
# test_limit before sourcing this file. IDRIS_MLIR_TIME_SCALE (make's
# time_scale) multiplies both, for a slower machine; a limit never passes a
# test, it only ends one. coreutils' timeout is $timeout_cmd
# (tools/host.sh).
. "$root/tools/host.sh"
if [ -z "$timeout_cmd" ]; then
  printf '%s\n' "test: $timeout_missing, so the test could hang"
  exit 1
fi
time_scale=${IDRIS_MLIR_TIME_SCALE:-1}
step_limit=$(( ${step_limit:-60} * time_scale ))
test_limit=$(( ${test_limit:-300} * time_scale ))
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

for lib_file in harness timing compile run heap mlir expect oracle chez properties e2e \
                profile determinism lit fuzz two-levels idris-lex bench upstream; do
  . "$root/tests/lib/$lib_file.sh"
done
unset lib_file
