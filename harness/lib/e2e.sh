# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# The end-to-end programs: compiled, run on each of their cases, and held
# to what each case says the run gives.
#
# Each fixture is compiled once with every module of the pipeline dumped,
# and everything that holds of a compilation is read off that one
# compilation and its dumps (lib/properties.sh); then the executable runs
# once per case.

# stdout_within_a_few_ulp EXPECTED OURS LINES: EXPECTED and OURS print the
# same text, except that the numbered lines LINES (one number per line) hold
# libm results, whose last places are the platform libm's, not the
# program's: libm is not correctly rounded, and the runtime calls the
# platform's, so a value recorded on one platform may differ from another's
# by a few units in the last place (four here). Every other line, and the
# number of lines, must agree exactly.
stdout_within_a_few_ulp() {
  awk -v lines="$3" '
    BEGIN { while ((getline n < lines) > 0) libm[n] = 1 }
    FILENAME == ARGV[1] { expected[FNR] = $0; n1 = FNR; next }
    { n2 = FNR
      if ($0 == expected[FNR]) next
      if (!(FNR in libm)) exit 1
      a = expected[FNR] + 0; b = $0 + 0
      m = (a < 0 ? -a : a); if ((b < 0 ? -b : b) > m) m = (b < 0 ? -b : b)
      d = a - b; if (d < 0) d = -d
      if (d > m * 2 ^ -50) exit 1 }
    END { if (n1 + 0 != n2 + 0) exit 1 }' "$1" "$2"
}

# e2e_io FIXTURE: an IO program, Main.idr and its other modules, compiled
# once, run on each of its cases (e2e_cases), and checked as every
# compilation is (universal) and by the checks of its modules
# (module_checks). A fixture with no `cases` directory is compiled only
# (a program that never ends). `packages` names installed packages it
# uses. It runs on a 1 MiB stack, or with `default-stack`, which says
# why, on the one programs get.
e2e_io() {
  io_fixture=$(cd "$1" && pwd)
  fixture_files_known "$io_fixture" || return
  cases_known "$io_fixture" || return
  if [ ! -d "$io_fixture/cases" ] && [ -f "$io_fixture/default-stack" ]; then
    say "fixture: compiled only, as it has no cases, so nothing reads default-stack"
    return
  fi
  io_packages=$(package_options "$io_fixture")
  io_stack=small
  [ -f "$io_fixture/default-stack" ] && io_stack=
  # Every compilation prints the module after each step (dump_options):
  # the checks of the fixture's modules read those dumps, and so do the
  # checks of every compilation (universal).
  mkdir "$work/ours"
  copy_fixture "$io_fixture" "$work/ours"
  io_dumps=$work/ours/build/exec/prog.dump
  # shellcheck disable=SC2046 # the dump options are words
  compile_program $io_packages $(dump_options "$io_dumps") "$work/ours/Main.idr" prog
  say "compile: exit $compiled"
  if [ "$compiled" -ne 0 ]; then
    show "$work/compile.out" "$work/compile.err"
    return
  fi
  artifacts "$work/ours" prog
  io_module=$(artifact_file "$work/ours" prog module)
  [ -d "$io_fixture/cases" ] && e2e_cases
  # shellcheck disable=SC2046 # one path per object, none with a space
  universal "$io_module" "$io_dumps" $(artifact_files "$work/ours" prog objects)
  heap_free "$io_fixture" "$io_dumps"
  module_checks "$io_fixture" "$io_module" "$io_dumps" "$(artifact_file "$work/ours" prog core)"
}

# The files a case directory may hold, each a field of the one record a
# case is: what the run reads, what it must give, and the marks of that
# run. cases_known and the README name them from here.
case_fields='stdin expected-stdout expected-exit expected-crash constant-stack live-cells libm-lines'

# cases_known FIXTURE: FIXTURE's `cases`, when it has one, is a directory
# of at least one case, each a directory named in letters, digits and
# dashes that holds only case_fields, and not both an expected-exit and an
# expected-crash (a crash's status is the runtime's, 1); otherwise a line
# naming each fault, and status 1. A case is never skipped: a file no
# field names, or a case that is no directory, would otherwise pass by
# never being read.
cases_known() {
  [ -e "$1/cases" ] || return 0
  ck_faults=
  ck_count=0
  if [ ! -d "$1/cases" ]; then
    say "cases: not a directory"
    return 1
  fi
  for ck_case in "$1"/cases/* "$1"/cases/.[!.]*; do
    [ -e "$ck_case" ] || continue
    ck_name=${ck_case##*/}
    case $ck_name in
      '' | -* | *[!A-Za-z0-9-]*)
        ck_faults="$ck_faults $ck_name (a name of letters, digits and dashes)"
        continue ;;
    esac
    if [ ! -d "$ck_case" ]; then
      ck_faults="$ck_faults $ck_name (not a directory)"
      continue
    fi
    ck_count=$((ck_count + 1))
    for ck_file in "$ck_case"/* "$ck_case"/.[!.]*; do
      [ -e "$ck_file" ] || continue
      case " $case_fields " in
        *" ${ck_file##*/} "*) [ -f "$ck_file" ] || ck_faults="$ck_faults $ck_name/${ck_file##*/} (not a file)" ;;
        *) ck_faults="$ck_faults $ck_name/${ck_file##*/} (no field of a case)" ;;
      esac
    done
    if [ -f "$ck_case/expected-exit" ] && [ -f "$ck_case/expected-crash" ]; then
      ck_faults="$ck_faults $ck_name (expected-exit beside expected-crash, whose status is 1)"
    fi
  done
  [ "$ck_count" -gt 0 ] || ck_faults="$ck_faults (no case)"
  [ -z "$ck_faults" ] && return 0
  say "cases:$ck_faults"
  return 1
}

# e2e_cases: the program e2e_io compiled, run once per case of its
# fixture's `cases`, in the order of their names, each held to its own
# expected files (e2e_case). One line when every case gives what it says,
# `cases: each as expected`; otherwise the lines of each case that did
# not, and no such line. The line does not count the cases, so a case
# added changes no transcript; cases_known has made sure that each case
# directory is read.
e2e_cases() {
  : > "$work/cases.failed"
  for ec_case in "$io_fixture"/cases/*/; do
    ec_case=${ec_case%/}
    e2e_case "$ec_case" "${ec_case##*/}" >> "$work/cases.failed"
  done
  if [ -s "$work/cases.failed" ]; then
    cat "$work/cases.failed"
  else
    say "cases: each as expected"
  fi
}

# e2e_case CASE NAME: the compiled program run on the case directory CASE:
#
#     stdin            the bytes on its standard input; none without it
#     expected-stdout  the bytes it writes on its standard output; none
#                      without it
#     expected-exit    its exit status, the first word; 0 without it
#     expected-crash   the cause the runtime names when the program
#                      crashes: then its status is 1 and its standard
#                      error is exactly `idris-mlir: <cause>`
#     constant-stack   the program loops in constant stack on a long
#                      input: its stdin is the case's stdin as many times
#                      over as the first word says, so many iterations
#                      that a loop keeping one frame per iteration exhausts
#                      the 1 MiB stack it runs on; the file says what loops
#     live-cells       the first word is how many heap cells are still
#                      live when main returns: a reference-count cycle the
#                      runtime does not collect. That count is taken off
#                      stderr, as 0 is; any other count stays and fails the
#                      empty-stderr check
#     libm-lines       the numbered output lines are libm results, whose
#                      last places are the platform libm's and may differ
#                      from expected-stdout's
#
# Without a crash its standard error is empty. Prints nothing when the run
# gives what the case says, and a line per difference otherwise, each
# naming the case.
e2e_case() {
  ec_dir=$1
  ec_name=$2
  ec_stdin=/dev/null
  [ -f "$ec_dir/stdin" ] && ec_stdin=$ec_dir/stdin
  if [ -f "$ec_dir/constant-stack" ]; then
    if [ -z "$io_stack" ]; then
      say "case $ec_name: constant-stack runs on the 1 MiB stack, which default-stack refuses"
      return
    fi
    repeated "$ec_stdin" "$(first_word "$ec_dir/constant-stack")" "$work/long-stdin" ||
      { say "case $ec_name: constant-stack names no count"; return; }
    ec_stdin=$work/long-stdin
  fi
  run_ours run "$work/ours/build/exec/prog" "$ec_stdin" $io_stack
  # A `live-cells` mark names how many cells a reference-count cycle keeps
  # at exit. The count is taken off stderr when it matches, as a count of 0
  # is, so the leak check still sees any other number.
  if [ -f "$ec_dir/live-cells" ]; then
    ec_live=$(first_word "$ec_dir/live-cells")
    if [ "$(tail -n 1 "$work/run.err")" = "idris-rt: live cells $ec_live" ]; then
      sed '$d' "$work/run.err" > "$work/run.err.counted"
      mv "$work/run.err.counted" "$work/run.err"
    fi
  fi
  ec_expected_exit=0
  [ -f "$ec_dir/expected-exit" ] && ec_expected_exit=$(first_word "$ec_dir/expected-exit")
  [ -f "$ec_dir/expected-crash" ] && ec_expected_exit=1
  if [ "$ran" -ne "$ec_expected_exit" ]; then
    if [ -f "$ec_dir/expected-crash" ]; then
      say "case $ec_name: exit $ran, but a crash exits 1"
    else
      say "case $ec_name: exit $ran, expected $ec_expected_exit"
    fi
  fi
  ec_expected_stdout=$ec_dir/expected-stdout
  [ -f "$ec_expected_stdout" ] || ec_expected_stdout=/dev/null
  if ! cmp -s "$ec_expected_stdout" "$work/run.out" &&
     ! { [ -f "$ec_dir/libm-lines" ] &&
         stdout_within_a_few_ulp "$ec_expected_stdout" "$work/run.out" "$ec_dir/libm-lines"; }; then
    say "case $ec_name: stdout differs from expected-stdout"
    diff "$ec_expected_stdout" "$work/run.out" | head -n 20 | sed 's/^/  | /'
  fi
  if [ -f "$ec_dir/expected-crash" ]; then
    { printf 'idris-mlir: '; cat "$ec_dir/expected-crash"; } > "$work/run.crash"
    if ! cmp -s "$work/run.crash" "$work/run.err"; then
      say "case $ec_name: stderr is not the crash expected-crash names"
      diff "$work/run.crash" "$work/run.err" | head -n 20 | sed 's/^/  | /'
    fi
  elif [ -s "$work/run.err" ]; then
    say "case $ec_name: stderr not empty"
    show "$work/run.err"
  fi
}

# fixture_files_known FIXTURE: every file of FIXTURE is one e2e_io reads,
# the test's own (run, expected, expected.<host>, suite, targets) or an
# Idris module; otherwise a line naming the others, and status 1. A
# misspelt mark, or one e2e_io does not read (an mlir.check: a property of
# a compiled module is stated by name in mlir.expect; a stdin: what a run
# reads is a case's), would otherwise be copied into the build and
# ignored, and its check would pass by never running.
fixture_files_known() {
  ffk_unknown=
  for ffk_file in "$1"/* "$1"/.[!.]*; do
    [ -f "$ffk_file" ] || continue
    case ${ffk_file##*/} in
      *.idr | run | expected | expected.* | suite | targets | packages | mlir.expect | heap-free | \
      covers | default-stack) ;;
      *) ffk_unknown="$ffk_unknown ${ffk_file##*/}" ;;
    esac
  done
  [ -z "$ffk_unknown" ] && return 0
  say "fixture: files no check reads:$ffk_unknown"
  return 1
}

# sem_case NAME: the generated semantics test NAME, one run of
# tests/semantics, which the runner runs once per test of
# harness/Sem.idr's table, NAME its parameter: an e2e fixture built in the
# work directory, whose Prog.idr and the expected-stdout of its one case
# are the runner's, which computes every case's value from what the
# primitive means and states once what the program prints when all agree,
# and whose Main.idr prints Prog.result. Main is partial: Prog.result may
# divide, and Idris does not hold a primitive division covering, since its
# divisor may be 0. Its cases are comparisons of fixed-width integers,
# which never need a heap cell (heap-free).
sem_case() {
  mkdir -p "$work/sem/cases/no-input"
  if ! "$runtests" --sem-program "$1" > "$work/sem/Prog.idr" 2> "$work/sem.err" ||
     ! "$runtests" --sem-expected "$1" > "$work/sem/cases/no-input/expected-stdout" 2>> "$work/sem.err"; then
    say "no semantics program $1"
    show "$work/sem.err"
    return
  fi
  cat > "$work/sem/Main.idr" <<'MAIN'
module Main

import Prelude
import Prog

partial
main : IO ()
main = printLn Prog.result
MAIN
  : > "$work/sem/heap-free"
  e2e_io "$work/sem"
}

# near_neighbour FIXTURE: a refused program's nearest accepted neighbour,
# FIXTURE/near, when it has one: a program differing from the refused one
# in the construct the rule refuses, which must compile and give what its
# cases say, so the rule is pinned from both sides. It is a program test's
# files (Main.idr, its modules, cases, marks) and none of a test's own;
# each line of its account is prefixed `near: `.
near_neighbour() {
  [ -e "$1/near" ] || return 0
  for nn_file in run expected suite targets; do
    if [ -e "$1/near/$nn_file" ]; then
      say "near: holds $nn_file, which is the refused test's own"
      return
    fi
  done
  if [ ! -f "$1/near/Main.idr" ]; then
    say "near: no Main.idr"
    return
  fi
  if header "$1/near/Main.idr" expect > /dev/null; then
    say "near: its Main.idr names a rule, but the neighbour is accepted"
    return
  fi
  (
    work=$work/near
    mkdir "$work"
    e2e_io "$1/near"
  ) | sed 's/^/near: /'
}

# module_checks FIXTURE EMITTED DUMPS CORE: every check of the
# compilation's modules that the fixture holds: mlir.expect
# (check_expect); covers, the prelude module whose every export the
# program uses (covers_prelude, on the program's Core, CORE, and its
# source).
module_checks() {
  [ -f "$1/mlir.expect" ] && check_expect "$1/mlir.expect" "$2" "$3"
  [ -f "$1/covers" ] && covers_prelude "$(first_word "$1/covers")" "$4" "$1"
  return 0
}
