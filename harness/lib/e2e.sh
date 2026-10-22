# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# The end-to-end programs: compiled, run on each of their cases, and held
# to what each case says the run gives.
#
# Each fixture is compiled once, with the passes' contracts, the promises
# every compiled program keeps and the properties it states of its stages
# checked as the passes run, and everything else that holds of a
# compilation is read off that one compilation (lib/properties.sh); then
# the executable runs once per case.

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
# compilation is (universal) and by the properties it states of its
# modules (stage_options). A fixture with no `cases` directory is compiled
# only (a program that never ends). `packages` names installed packages it
# uses.
e2e_io() {
  io_fixture=$(cd "$1" && pwd)
  fixture_files_known "$io_fixture" || return
  cases_known "$io_fixture" || return
  io_packages=$(package_options "$io_fixture")
  # The compilation checks every pass's contracts and the promises every
  # compiled program keeps as it runs (--idr-contracts), and the
  # properties the fixture states of a stage after every pass of that stage
  # (stage_options); the executable links the checked runtime, which ends a
  # run that returns with a cell still live as the runtime's internal error.
  mkdir "$work/ours"
  copy_fixture "$io_fixture" "$work/ours"
  # The checks, one per line, which a compilation from the emitted module
  # takes too (universal); the packages are the frontend's alone.
  { say --idr-contracts; stage_options "$io_fixture"; } > "$work/options"
  # shellcheck disable=SC2046,SC2086 # one option per line, none with a space; the packages are words
  compile_checked $io_packages $(cat "$work/options") "$work/ours/Main.idr" prog
  say "compile: exit $compiled"
  if [ "$compiled" -ne 0 ]; then
    show "$work/compile.out" "$work/compile.err"
    return
  fi
  artifacts "$work/ours" prog
  [ -d "$io_fixture/cases" ] && e2e_cases
  # shellcheck disable=SC2046 # one path per object, none with a space
  universal "$io_fixture" "$(artifact_file "$work/ours" prog module)" "$work/options" \
    $(artifact_files "$work/ours" prog objects)
  [ -f "$io_fixture/heap-free" ] && say "heap: nothing is allocated on the heap"
  [ -f "$io_fixture/mlir.expect" ] && say "mlir.expect: holds"
  [ -f "$io_fixture/covers" ] &&
    covers_prelude "$(first_word "$io_fixture/covers")" "$(artifact_file "$work/ours" prog core)" "$io_fixture"
  return 0
}

# The files a case directory may hold, each a field of the one record a
# case is: what the run reads, what it must give, and the marks of that
# run. cases_known and the README name them from here.
case_fields='stdin expected-stdout expected-ending expected-stderr libm-lines'

# cases_known FIXTURE: FIXTURE's `cases`, when it has one, is a directory
# of at least one case, each a directory named in letters, digits and
# dashes that holds only case_fields; otherwise a line naming each fault,
# and status 1. A case is never skipped: a file no field names, or a case
# that is no directory, would otherwise pass by never being read.
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

# e2e_case CASE NAME: the compiled program, $work/ours/build/exec/prog, run
# on the case directory CASE:
#
#     stdin            the bytes on its standard input; none without it
#     expected-stdout  the bytes it writes on its standard output; none
#                      without it
#     expected-ending  how the run ends, one line, the specification's
#                      ending as Facts.idr writes it; `returned` without it
#     expected-stderr  the bytes it writes on its standard error, the
#                      runtime's line for its ending among them; none
#                      without it
#     libm-lines       the numbered output lines are libm results, whose
#                      last places are the platform libm's and may differ
#                      from expected-stdout's
#
# The status the run must end with, an exit code or a signal, is the
# runner's to compute from the ending, from the specification's table
# (`runtests --case-status`): no status is spelled here. The shell reports
# a process a signal ended as 128 plus the signal's number, which `kill -l`
# names. Prints nothing when the run gives what the case says, and a line
# per difference otherwise, each naming the case.
e2e_case() {
  ec_dir=$1
  ec_name=$2
  ec_stdin=/dev/null
  [ -f "$ec_dir/stdin" ] && ec_stdin=$ec_dir/stdin
  if ! ec_expected=$("$runtests" --case-status "$ec_dir" 2> "$work/case.err"); then
    say "case $ec_name: its ending cannot be read"
    show "$work/case.err"
    return
  fi
  run_program run "$work/ours/build/exec/prog" "$ec_stdin"
  # What the run gave, which the run of the same program compiled with
  # actions skipped must give too (skips_hold).
  mkdir -p "$work/case-runs"
  cp "$work/run.out" "$work/case-runs/$ec_name.out"
  cp "$work/run.err" "$work/case-runs/$ec_name.err"
  printf '%s\n' "$ran" > "$work/case-runs/$ec_name.status"
  ec_got="code $ran"
  [ "$ran" -gt 128 ] && ec_got="signal $(kill -l "$((ran - 128))")"
  if [ "$ec_got" != "$ec_expected" ]; then
    say "case $ec_name: ended by $ec_got, expected $ec_expected"
  fi
  ec_expected_stdout=$ec_dir/expected-stdout
  [ -f "$ec_expected_stdout" ] || ec_expected_stdout=/dev/null
  if ! cmp -s "$ec_expected_stdout" "$work/run.out" &&
     ! { [ -f "$ec_dir/libm-lines" ] &&
         stdout_within_a_few_ulp "$ec_expected_stdout" "$work/run.out" "$ec_dir/libm-lines"; }; then
    say "case $ec_name: stdout differs from expected-stdout"
    diff "$ec_expected_stdout" "$work/run.out" | head -n 20 | sed 's/^/  | /'
  fi
  ec_expected_stderr=$ec_dir/expected-stderr
  [ -f "$ec_expected_stderr" ] || ec_expected_stderr=/dev/null
  if ! cmp -s "$ec_expected_stderr" "$work/run.err"; then
    say "case $ec_name: stderr differs from expected-stderr"
    diff "$ec_expected_stderr" "$work/run.err" | head -n 20 | sed 's/^/  | /'
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
      covers) ;;
      *) ffk_unknown="$ffk_unknown ${ffk_file##*/}" ;;
    esac
  done
  [ -z "$ffk_unknown" ] && return 0
  say "fixture: files no check reads:$ffk_unknown"
  return 1
}

# sem_case NAME: the generated semantics test NAME, one run of
# tests/semantics, which the runner runs once per test of
# harness/Sem.idr's table, NAME its parameter: two e2e fixtures built in
# the work directory, one table checked by two programs, whose Prog.idr,
# input and the expected-stdout of their one case are the runner's, which
# computes every case's value from what the primitive means and states
# once what a program prints when all agree. In the first, every operand
# is written in the program, so the compiler computes each case while it
# compiles; its cases are comparisons of fixed-width integers, which never
# need a heap cell (heap-free). In the second, every operand is read from
# the case's stdin, so only the compiled program's arithmetic answers; it
# reads lines into lists, which live on the heap. Its account is the
# first's form, each line prefixed `stdin: `. Main is partial: Prog.result
# may divide, and Idris does not hold a primitive division covering, since
# its divisor may be 0.
sem_case() {
  mkdir -p "$work/sem/cases/no-input" "$work/sem-stdin/cases/operands"
  if ! "$runtests" --sem-program written "$1" > "$work/sem/Prog.idr" 2> "$work/sem.err" ||
     ! "$runtests" --sem-expected "$1" > "$work/sem/cases/no-input/expected-stdout" 2>> "$work/sem.err" ||
     ! "$runtests" --sem-program stdin "$1" > "$work/sem-stdin/Prog.idr" 2>> "$work/sem.err" ||
     ! "$runtests" --sem-stdin "$1" > "$work/sem-stdin/cases/operands/stdin" 2>> "$work/sem.err"; then
    say "no semantics program $1"
    show "$work/sem.err"
    return
  fi
  cp "$work/sem/cases/no-input/expected-stdout" "$work/sem-stdin/cases/operands/expected-stdout"
  cat > "$work/sem/Main.idr" <<'MAIN'
module Main

import Prelude
import Prog

partial
main : IO ()
main = printLn Prog.result
MAIN
  cat > "$work/sem-stdin/Main.idr" <<'MAIN'
module Main

import Prelude
import Prog

partial
main : IO ()
main = Prog.result >>= printLn
MAIN
  : > "$work/sem/heap-free"
  e2e_io "$work/sem"
  sem_stdin=$work/sem-stdin
  (
    work=$work/given-on-stdin
    mkdir "$work"
    e2e_io "$sem_stdin"
  ) | sed 's/^/stdin: /'
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
