# What the golden tests' run scripts share (docs/plan.md section 9). A run
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
# Makefile's (TC-PIN-2).

idris_mlir=$1
root=${IDRIS_MLIR_ROOT:?IDRIS_MLIR_ROOT must name the repository}
toolchain=$root/.toolchain
llvm_bin=$toolchain/llvm/bin
pinned_cc=$toolchain/gcc/bin/gcc
idris_mlir_cc=$root/build/dev/foreign/idr/idris-mlir-cc
idris_mlir_opt=$root/build/dev/foreign/idr/idris-mlir-opt
# Stock Idris 2, the reference implementation (SEM-REF-1).
idris2=$toolchain/idris2/bin/idris2
runtests=$root/tests/build/exec/runtests
compile_sh=$root/tools/compile.sh
here=$(pwd)

work=$(mktemp -d "${TMPDIR:-/tmp}/idris-mlir-test.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT
trap 'exit 1' HUP INT TERM

# Commands under test time out after ten minutes, as they always have.
if command -v timeout > /dev/null 2>&1; then bounded='timeout 600'; else bounded=; fi

# say TEXT...: one line of the test's output, printed as is.
say() {
  printf '%s\n' "$*"
}

# show FILE...: files a failure is about, indented.
show() {
  cat "$@" 2> /dev/null | head -n 40 | sed 's/^/  | /'
}

# copy_fixture FIXTURE DEST: a fixture file, or the files of a fixture
# directory but the golden test's own.
copy_fixture() {
  if [ -d "$1" ]; then
    for copy_file in "$1"/* "$1"/.[!.]*; do
      [ -f "$copy_file" ] || continue
      case ${copy_file##*/} in run|expected|output) continue ;; esac
      cp -p "$copy_file" "$2/"
    done
  else
    cp -p "$1" "$2/"
  fi
}

# fixture_name FIXTURE: its directory or file name, without `.idr`.
fixture_name() {
  if [ -d "$1" ]; then
    fixture_name_dir=$(cd "$1" && pwd)
    say "${fixture_name_dir##*/}"
  else
    fixture_name_file=${1##*/}
    say "${fixture_name_file%.idr}"
  fi
}

# first_word FILE: its first whitespace-separated word.
first_word() {
  awk '{ for (i = 1; i <= NF; i++) { print $i; exit } }' "$1"
}

# compile_program [--int|--io] [-p PACKAGE]... [--directive D]... SOURCE OUTPUT:
# DRV-FLOW-1 or DRV-FLOW-2 through tools/compile.sh, the one copy of the
# chain. Its output is in $work/compile.out and $work/compile.err, its exit
# status in $compiled.
compile_program() {
  IDRIS_MLIR=$idris_mlir "$compile_sh" "$@" > "$work/compile.out" 2> "$work/compile.err"
  compiled=$?
}

# artifacts DIR NAME...: every NAME is a non-empty file somewhere under
# DIR/build.
artifacts() {
  artifacts_dir=$1
  shift
  artifacts_found=
  artifacts_missing=
  for artifacts_name in "$@"; do
    if [ -n "$(find "$artifacts_dir/build" -type f -name "$artifacts_name" 2> /dev/null | head -n 1)" ] &&
       [ -z "$(find "$artifacts_dir/build" -type f -name "$artifacts_name" -size 0 2> /dev/null)" ]; then
      artifacts_found="$artifacts_found $artifacts_name"
    else
      artifacts_missing="$artifacts_missing $artifacts_name"
    fi
  done
  say "artifacts:$artifacts_found"
  [ -z "$artifacts_missing" ] || say "missing or empty:$artifacts_missing"
}

# no_artifacts DIR: no .core, .mlir or object file under DIR/build.
no_artifacts() {
  no_artifacts_left=$(find "$1/build" -type f \( -name '*.core' -o -name '*.mlir' -o -name '*.o' \) 2> /dev/null | sed "s|^$1/||" | sort)
  if [ -z "$no_artifacts_left" ]; then
    say "artifacts: none"
  else
    say "artifacts left after a rejection:" $no_artifacts_left
  fi
}

# run_program NAME EXE INPUT [small]: runs EXE with stdin from INPUT, its
# stdout and stderr in $work/NAME.out and $work/NAME.err, its exit status in
# $ran. With `small`, on a 1 MiB stack (SEM-RES-2).
run_program() {
  if [ "${4-}" = small ]; then
    ( ulimit -s 1024 && exec $bounded "$2" ) < "$3" > "$work/$1.out" 2> "$work/$1.err"
  else
    $bounded "$2" < "$3" > "$work/$1.out" 2> "$work/$1.err"
  fi
  ran=$?
}

# empty NAME FILE: FILE is empty.
empty() {
  if [ -s "$2" ]; then say "$1: not empty"; show "$2"; else say "$1: empty"; fi
}

# rule: TEST-HEAP-1, LOW-EXT-1
# heap_free OBJECT SYMBOL...: the object's undefined symbols (llvm-nm) are
# among SYMBOLs: no malloc, no runtime, no other libc call.
heap_free() {
  heap_object=$1
  shift
  if ! "$llvm_bin/llvm-nm" --undefined-only --format=just-symbols "$heap_object" > "$work/nm.out" 2> "$work/nm.err"; then
    say "object: llvm-nm failed"
    show "$work/nm.err"
    return
  fi
  heap_extra=
  for heap_symbol in $(sort -u "$work/nm.out"); do
    case " $* " in
      *" $heap_symbol "*) ;;
      *) heap_extra="$heap_extra $heap_symbol" ;;
    esac
  done
  if [ -z "$heap_extra" ]; then
    say "object: no undefined symbol outside LOW-EXT-1's set"
  else
    say "object: undefined symbols outside LOW-EXT-1's set:$heap_extra"
  fi
}

v0_symbols='write _exit'
v1_symbols='write read _exit'
# LOW-EXT-1: v2 programs may also call these libm functions, including the
# ones LLVM substitutes for pow (SEM-DEV-2).
v2_symbols="$v1_symbols exp log pow sin cos tan asin acos atan sqrt floor ceil exp2 ldexp"

# filecheck CHECKS INPUT: the pinned FileCheck.
filecheck() {
  if "$llvm_bin/FileCheck" "$1" --input-file="$2" > "$work/filecheck.log" 2>&1; then
    say "FileCheck ${1##*/}: ok"
  else
    say "FileCheck ${1##*/} on ${2##*/}: failed"
    show "$work/filecheck.log"
  fi
}

# rule: TEST-ORACLE-1, SEM-REF-1, SEM-LIT-1
# check_oracle FIXTURE: stock Idris checks the fixture's Oracle.idr, so its
# evaluator agrees with the fixture's expectation.
check_oracle() {
  mkdir "$work/oracle"
  copy_fixture "$1" "$work/oracle"
  (cd "$work/oracle" && $bounded "$idris2" --no-banner --no-color --no-prelude --check Oracle.idr) > "$work/oracle.log" 2>&1
  check_oracle_status=$?
  if [ "$check_oracle_status" -eq 0 ]; then
    say "oracle: stock idris2 checks Oracle.idr"
  else
    say "oracle: stock idris2 rejects Oracle.idr (exit $check_oracle_status)"
    show "$work/oracle.log"
  fi
}

# oracle_value FIXTURE: the literal of `check : Prog.main = <literal>` in its
# Oracle.idr, which has exactly one `check = Refl`; or a complaint.
oracle_value() {
  oracle_literal=$(sed -n 's/^check[[:space:]]*:[[:space:]]*Prog\.main[[:space:]]*=[[:space:]]*\(-\{0,1\}[0-9][0-9]*\)[[:space:]]*$/\1/p' "$1/Oracle.idr" | head -n 1)
  oracle_refls=$(grep -c '^check[[:space:]]*=[[:space:]]*Refl[[:space:]]*$' "$1/Oracle.idr")
  if [ -z "$oracle_literal" ]; then
    say "Oracle.idr must contain \`check : Prog.main = <integer literal>\`"
    return 1
  fi
  if [ "$oracle_refls" -ne 1 ]; then
    say "Oracle.idr must contain one \`check = Refl\`"
    return 1
  fi
  say "$oracle_literal"
}

# compile_v0 DIR: DRV-FLOW-1 on DIR/Prog.idr, to DIR/build/exec/Prog.
compile_v0() {
  compile_program --int "$1/Prog.idr" "$1/build/exec/Prog"
  say "compile: exit $compiled"
  if [ "$compiled" -ne 0 ]; then
    show "$work/compile.out" "$work/compile.err"
    return 1
  fi
  artifacts "$1" Prog.core Prog.mlir Prog.o Prog
}

# rule: TEST-CRASH-1, TEST-ORACLE-2, SEM-CRASH-1, SEM-PROG-1, DRV-FLOW-1, FE-ENTRY-2, CORE-DUMP-1
# e2e_v0 FIXTURE: a `main : Int` program, Prog.idr, whose exit status is
# its Oracle.idr's literal mod 256 (TEST-ORACLE-1) or its expected-exit
# (TEST-ORACLE-2), or which crashes with its expected-crash (TEST-CRASH-1).
e2e_v0() {
  v0_expected=
  if [ -f "$1/Oracle.idr" ]; then
    v0_expected=$(oracle_value "$1") || { say "$v0_expected"; return; }
    check_oracle "$1"
  fi
  mkdir "$work/e2e"
  copy_fixture "$1" "$work/e2e"
  compile_v0 "$work/e2e" || return
  run_program prog "$work/e2e/build/exec/Prog" /dev/null small
  if [ -f "$1/expected-crash" ]; then
    v0_cause=$(cat "$1/expected-crash")
    if [ "$ran" -eq 1 ]; then say "run: exit 1, a crash"; else say "run: exit $ran, but a crash exits 1"; fi
    empty stdout "$work/prog.out"
    if grep -qF -- "$v0_cause" "$work/prog.err"; then
      say "stderr: names the cause in expected-crash"
    else
      say "stderr: lacks the cause in expected-crash"
      show "$work/prog.err"
    fi
  else
    [ -n "$v0_expected" ] || v0_expected=$(first_word "$1/expected-exit")
    v0_status=$(( (v0_expected % 256 + 256) % 256 ))
    if [ "$ran" -eq "$v0_status" ]; then
      say "run: exit status as expected"
    else
      say "run: exit $ran, expected $v0_expected mod 256 = $v0_status"
    fi
    empty stdout "$work/prog.out"
    empty stderr "$work/prog.err"
  fi
  heap_free "$work/e2e/build/exec/Prog.o" $v0_symbols
  if [ -f "$1/mlir.check" ]; then
    filecheck "$1/mlir.check" "$(find "$work/e2e/build" -type f -name Prog.mlir | sort | head -n 1)"
  fi
}

# rule: TEST-IO-1, TEST-DIFF-1, TEST-ELIM-1, SEM-DEV-1, DRV-FLOW-2, DRV-DUMP-1, FE-ENTRY-4
# e2e_io FIXTURE: an IO program, Main.idr and its other modules, run on its
# stdin against its expected-stdout and expected-exit or expected-crash,
# with its core.check, translate.check and mlir.check. The stock Chez
# backend compiles the same program, and must print the same stdout and
# exit with the same status (TEST-DIFF-1); with `oracle-chez` it is the only
# oracle of stdout. `packages` names installed packages it uses.
e2e_io() {
  io_fixture=$(cd "$1" && pwd)
  io_version=$(cd "$io_fixture/.." && pwd)
  io_version=${io_version##*/}
  io_stdin=/dev/null
  [ -f "$io_fixture/stdin" ] && io_stdin=$io_fixture/stdin
  io_expected_exit=0
  [ -f "$io_fixture/expected-exit" ] && io_expected_exit=$(first_word "$io_fixture/expected-exit")
  io_packages=
  if [ -f "$io_fixture/packages" ]; then
    for io_package in $(cat "$io_fixture/packages"); do io_packages="$io_packages -p $io_package"; done
  fi
  io_directives=
  if [ -f "$io_fixture/core.check" ] || [ -f "$io_fixture/translate.check" ]; then
    io_directives='--directive dump-core'
  fi
  [ -f "$io_fixture/Oracle.idr" ] && check_oracle "$io_fixture"

  mkdir "$work/ours"
  copy_fixture "$io_fixture" "$work/ours"
  compile_program --io $io_packages $io_directives "$work/ours/Main.idr" prog
  say "compile: exit $compiled"
  if [ "$compiled" -ne 0 ]; then
    show "$work/compile.out" "$work/compile.err"
    return
  fi
  artifacts "$work/ours" prog.core prog.mlir prog.o prog
  run_program ours "$work/ours/build/exec/prog" "$io_stdin" small
  io_ours_status=$ran

  if [ -f "$io_fixture/expected-crash" ]; then
    io_crash=$(cat "$io_fixture/expected-crash")
    if [ "$ran" -eq 1 ]; then say "run: exit 1, a crash"; else say "run: exit $ran, but a crash exits 1"; fi
  else
    io_crash=
    if [ "$ran" -eq "$io_expected_exit" ]; then
      say "run: exit status as expected"
    else
      say "run: exit $ran, expected $io_expected_exit"
    fi
  fi
  if [ -f "$io_fixture/oracle-chez" ]; then
    say "stdout: compared with Chez's alone (oracle-chez)"
  else
    io_expected_stdout=$io_fixture/expected-stdout
    if [ ! -f "$io_expected_stdout" ]; then
      io_expected_stdout=$work/expected-stdout
      : > "$io_expected_stdout"
    fi
    if cmp -s "$io_expected_stdout" "$work/ours.out"; then
      say "stdout: as expected"
    else
      say "stdout: differs from expected-stdout"
      diff "$io_expected_stdout" "$work/ours.out" | head -n 20 | sed 's/^/  | /'
    fi
  fi
  if [ -z "$io_crash" ]; then
    empty stderr "$work/ours.err"
  elif grep -qF -- "$io_crash" "$work/ours.err"; then
    say "stderr: names the cause in expected-crash"
  else
    say "stderr: lacks the cause in expected-crash"
    show "$work/ours.err"
  fi

  case $io_version in
    v2|v3) heap_free "$work/ours/build/exec/prog.o" $v2_symbols ;;
    *) heap_free "$work/ours/build/exec/prog.o" $v1_symbols ;;
  esac
  [ -f "$io_fixture/core.check" ] &&
    filecheck "$io_fixture/core.check" "$work/ours/build/exec/prog.dump/02-simplify.core"
  [ -f "$io_fixture/translate.check" ] &&
    filecheck "$io_fixture/translate.check" "$work/ours/build/exec/prog.dump/01-translate.core"
  [ -f "$io_fixture/mlir.check" ] &&
    filecheck "$io_fixture/mlir.check" "$work/ours/build/exec/prog.mlir"

  # The Chez oracle: a second compile of the same program, run on the same
  # input.
  mkdir "$work/chez"
  copy_fixture "$io_fixture" "$work/chez"
  (cd "$work/chez" && $bounded "$idris2" --no-banner --no-color --no-prelude $io_packages \
     --cg chez -o prog Main.idr) > "$work/chez.log" 2>&1
  io_chez_built=$?
  say "chez: compile exit $io_chez_built"
  if [ "$io_chez_built" -ne 0 ]; then
    show "$work/chez.log"
    return
  fi
  run_program chez "$work/chez/build/exec/prog" "$io_stdin"
  io_chez_status=$ran
  io_same=no
  if cmp -s "$work/ours.out" "$work/chez.out"; then
    io_same=yes
  elif [ -n "$io_crash" ]; then
    # SEM-DEV-1: Chez writes some crash messages to stdout.
    io_bytes=$(wc -c < "$work/ours.out" | tr -d ' ')
    if head -c "$io_bytes" "$work/chez.out" | cmp -s - "$work/ours.out"; then
      tail -c +"$((io_bytes + 1))" "$work/chez.out" > "$work/chez.rest"
      if [ ! -s "$work/chez.rest" ] || [ "$(head -c 7 "$work/chez.rest")" = "ERROR: " ]; then
        io_same=yes
      fi
    fi
  fi
  if [ "$io_same" = no ]; then
    say "chez: stdout differs (< this compiler, > Chez)"
    diff "$work/ours.out" "$work/chez.out" | head -n 20 | sed 's/^/  | /'
  elif [ -n "$io_crash" ]; then
    say "chez: same stdout"
  elif [ "$io_chez_status" -eq "$io_ours_status" ]; then
    say "chez: same stdout and exit status"
  else
    say "chez: same stdout, but Chez exited $io_chez_status and this compiler $io_ours_status"
  fi
}

# sem_case NAME: the TEST-SEM-1 test NAME, a v0 fixture whose Prog.idr the
# runner generates (tests/Sem.idr) and whose Oracle.idr proves
# `Prog.main = 0`.
sem_case() {
  mkdir "$work/sem"
  if ! "$runtests" --sem-program "$1" > "$work/sem/Prog.idr" 2> "$work/sem.err"; then
    say "no TEST-SEM-1 program $1"
    show "$work/sem.err"
    return
  fi
  cat > "$work/sem/Oracle.idr" <<'ORACLE'
module Oracle

import Builtin
import Prog

check : Prog.main = 0
check = Refl
ORACLE
  e2e_v0 "$work/sem"
}

# header FILE FIELD: the value of `-- FIELD: <value>` among the lines of that
# form that start a profile fixture; the status is 1 without one.
header() {
  awk -v field="$2" '
    !/^--[ \t]*(expect|message|exit|stdout|packages):/ { exit }
    {
      key = $0; sub(/^--[ \t]*/, "", key); sub(/:.*$/, "", key)
      if (key == field) { value = $0; sub(/^--[ \t]*[a-z]+:[ \t]*/, "", value); found = 1 }
    }
    END { if (found) { print value; exit 0 } exit 1 }' "$1"
}

# reported_line FILE: the first line number of the first Idris location,
# `<file>:<line>:<col>--<line>:<col>`, in FILE.
reported_line() {
  grep -oE '(^|[[:space:]])[A-Za-z0-9_/.-]+:[0-9]+:[0-9]+--[0-9]+:[0-9]+([^A-Za-z0-9_]|$)' "$1" |
    head -n 1 | sed 's/^[[:space:]]*[A-Za-z0-9_/.-]*:\([0-9]*\):.*/\1/'
}

# profile_prepare FIXTURE: the fixture in $work/fixture, a single file as
# Main.idr.
profile_prepare() {
  mkdir "$work/fixture"
  if [ -d "$1" ]; then
    copy_fixture "$1" "$work/fixture"
  else
    cp "$1" "$work/fixture/Main.idr"
  fi
}

# profile_compile: $work/fixture/Main.idr to build/exec/Main, through
# DRV-FLOW-2 with the packages its header names if its main is IO, and
# DRV-FLOW-1 otherwise.
profile_compile() {
  profile_main=$work/fixture/Main.idr
  if grep -Eq '^main[[:space:]]*:[[:space:]]*IO([^[:alnum:]_]|$)' "$profile_main"; then
    profile_packages=
    for profile_package in $(header "$profile_main" packages); do
      profile_packages="$profile_packages -p $profile_package"
    done
    compile_program --io $profile_packages "$profile_main" Main
  else
    compile_program --int "$profile_main" "$work/fixture/build/exec/Main"
  fi
}

# rule: TEST-REJ-1, FE-ART-1, DIAG-FMT-1, DIAG-LOC-1, DIAG-EXIT-1, DIAG-CODE-1, DIAG-ONE-1, PROF-GEN-2
# profile_reject FIXTURE: `tests/profile/vN/reject/<RULE-ID>-<desc>.idr`, or a
# directory of that name holding Main.idr and its other modules, whose first
# line is `-- expect: <RULE-ID> line <n>` (and then, optionally,
# `-- message: <text>`). It is rejected with exit status 1 and exactly one
# `unsupported (<RULE-ID>)`, reported on line n, and leaves no artifact.
profile_reject() {
  if [ -d "$1" ]; then reject_main=$1/Main.idr; else reject_main=$1; fi
  reject_name=$(fixture_name "$1")
  reject_expect=$(header "$reject_main" expect)
  reject_rule=$(printf '%s\n' "$reject_expect" | sed -n 's/^\([A-Z0-9-][A-Z0-9-]*\) line \([0-9][0-9]*\)$/\1/p')
  reject_line=$(printf '%s\n' "$reject_expect" | sed -n 's/^\([A-Z0-9-][A-Z0-9-]*\) line \([0-9][0-9]*\)$/\2/p')
  if [ -z "$reject_rule" ]; then
    say "$reject_name: the first line must be '-- expect: <RULE-ID> line <n>'"
    return
  fi
  case $reject_name in
    "$reject_rule"*) ;;
    *) say "$reject_name does not start with $reject_rule"; return ;;
  esac
  profile_prepare "$1"
  profile_compile
  say "compile: exit $compiled"
  cat "$work/compile.out" "$work/compile.err" > "$work/compile.all"
  reject_count=$(grep -o 'unsupported (' "$work/compile.all" | wc -l | tr -d ' ')
  if grep -qF "unsupported ($reject_rule)" "$work/compile.all" && [ "$reject_count" -eq 1 ]; then
    say "unsupported ($reject_rule): the only error"
  else
    say "unsupported ($reject_rule): expected once, among $reject_count unsupported errors"
    show "$work/compile.all"
  fi
  reject_reported=$(reported_line "$work/compile.all")
  if [ "$reject_reported" = "$reject_line" ]; then
    say "line: as the header says"
  else
    say "line: ${reject_reported:-none} reported, the header says $reject_line"
  fi
  if reject_message=$(header "$reject_main" message); then
    if grep -qF -- "$reject_message" "$work/compile.all"; then
      say "message: as the header says"
    else
      say "message: not in the output: $reject_message"
    fi
  fi
  no_artifacts "$work/fixture"
}

# rule: TEST-ACC-1, TEST-VER-1, PROF-GEN-4
# profile_accept FIXTURE: `tests/profile/vN/accept/<RULE-ID>-<desc>.idr`, or a
# directory of that name holding Main.idr: it compiles with every artifact
# written. With `-- exit: <status>` or `-- stdout: <text with \n escapes>` in
# its header it also runs, with those, and with nothing on stderr.
profile_accept() {
  if [ -d "$1" ]; then accept_main=$1/Main.idr; else accept_main=$1; fi
  profile_prepare "$1"
  profile_compile
  say "compile: exit $compiled"
  if [ "$compiled" -ne 0 ]; then
    show "$work/compile.out" "$work/compile.err"
    return
  fi
  artifacts "$work/fixture" Main.core Main.mlir Main.o Main
  accept_exit=$(header "$accept_main" exit)
  accept_has_exit=$?
  accept_stdout=$(header "$accept_main" stdout)
  accept_has_stdout=$?
  [ "$accept_has_exit" -eq 0 ] || [ "$accept_has_stdout" -eq 0 ] || return 0
  run_program accept "$work/fixture/build/exec/Main" /dev/null
  if [ "$accept_has_exit" -eq 0 ]; then
    accept_exit=$(printf '%s' "$accept_exit" | tr -d ' \t')
    if [ "$ran" -eq "$accept_exit" ]; then
      say "run: exit status as the header says"
    else
      say "run: exit $ran, the header says $accept_exit"
    fi
  else
    say "run: exit $ran"
  fi
  printf '%b' "$accept_stdout" > "$work/accept.expected"
  if cmp -s "$work/accept.expected" "$work/accept.out"; then
    say "stdout: as the header says"
  else
    say "stdout: differs from the header"
    diff "$work/accept.expected" "$work/accept.out" | head -n 20 | sed 's/^/  | /'
  fi
  empty stderr "$work/accept.err"
}

# rule: TEST-DET-1, FE-DET-1, DRV-DET-1
# determinism FLOW FIXTURE: two compilations of the fixture give
# byte-identical .core, .mlir, object and executable. FLOW is `v0`, DRV-FLOW-1
# on Prog.idr, or `io`, DRV-FLOW-2 on Main.idr.
determinism() {
  mkdir "$work/det"
  copy_fixture "$2" "$work/det"
  for det_round in 1 2; do
    rm -rf "$work/det/build"
    if [ "$1" = v0 ]; then
      compile_program --int "$work/det/Prog.idr" "$work/det/build/exec/Prog"
      det_core=$(find "$work/det/build" -type f -name Prog.core | sort | head -n 1)
      det_mlir=$(find "$work/det/build" -type f -name Prog.mlir | sort | head -n 1)
      det_object=$work/det/build/exec/Prog.o
      det_executable=$work/det/build/exec/Prog
    else
      compile_program --io "$work/det/Main.idr" prog
      det_core=$work/det/build/exec/prog.core
      det_mlir=$work/det/build/exec/prog.mlir
      det_object=$work/det/build/exec/prog.o
      det_executable=$work/det/build/exec/prog
    fi
    say "compile $det_round: exit $compiled"
    if [ "$compiled" -ne 0 ]; then
      show "$work/compile.out" "$work/compile.err"
      return
    fi
    mkdir "$work/round$det_round"
    cp "$det_core" "$work/round$det_round/core" 2> /dev/null
    cp "$det_mlir" "$work/round$det_round/mlir" 2> /dev/null
    cp "$det_object" "$work/round$det_round/object" 2> /dev/null
    cp "$det_executable" "$work/round$det_round/executable" 2> /dev/null
  done
  for det_kind in core mlir object executable; do
    if [ ! -f "$work/round1/$det_kind" ] || [ ! -f "$work/round2/$det_kind" ]; then
      say "$det_kind: missing"
    elif cmp -s "$work/round1/$det_kind" "$work/round2/$det_kind"; then
      say "$det_kind: identical"
    else
      say "$det_kind: differs between two compilations"
    fi
  done
}

# sed_escape TEXT: TEXT as the replacement of a `s|...|...|` command.
sed_escape() {
  printf '%s\n' "$1" | sed 's/[\\|&]/\\&/g'
}

# lit_stage CMD...: one command of a RUN line's pipeline; its failure fails
# the line, as lit's pipefail does.
lit_stage() {
  "$@"
  lit_stage_status=$?
  [ "$lit_stage_status" -eq 0 ] || say "$1 exited $lit_stage_status" >> "$work/lit.failed"
  return "$lit_stage_status"
}

# lit_status N CMD... (`%status N CMD`): CMD exits with exactly status N.
lit_status() {
  lit_expected_status=$1
  shift
  "$@"
  lit_got_status=$?
  [ "$lit_got_status" -eq "$lit_expected_status" ] && return 0
  say "$1 exited $lit_got_status, expected $lit_expected_status" >&2
  return 1
}

# rule: TEST-IDR-1
# lit FILE: the `// RUN:` lines of a dialect test, run as lit's internal
# shell ran them, with no lit and no Python: %s is FILE, %t a path in the
# work directory, %cc the pinned C compiler, and `%status N CMD` checks that
# CMD exits with status N. A line fails when any command of its pipelines
# fails (pipefail); a trailing \ continues it on the next RUN line.
# idris-mlir-opt, idris-mlir-cc and the pinned LLVM's FileCheck, not and
# count come first on PATH, and `echo -n` omits the newline.
lit() {
  lit_file=$(cd "$(dirname "$1")" && pwd)/${1##*/}
  sed -n 's/^[[:space:]]*\/\/[[:space:]]*RUN:[[:space:]]*//p' "$lit_file" |
    awk '{ sub(/[ \t]+$/, "") }
         /\\$/ { sub(/\\$/, ""); joined = joined $0; next }
         { print joined $0; joined = "" }
         END { if (joined != "") print joined }' > "$work/lit.lines"
  PATH=$root/build/dev/foreign/idr:$llvm_bin:$PATH
  export PATH
  lit_n=0
  while IFS= read -r lit_line; do
    lit_n=$((lit_n + 1))
    lit_command=$(printf '%s\n' "$lit_line" | sed \
      -e "s|%status|lit_status|g" \
      -e "s|%cc|$(sed_escape "$pinned_cc")|g" \
      -e "s|%s|$(sed_escape "$lit_file")|g" \
      -e "s|%t|$(sed_escape "$work/t")|g" \
      -e 's/ | / | lit_stage /g' \
      -e 's/^/lit_stage /')
    : > "$work/lit.failed"
    (
      echo() {
        if [ "${1-}" = -n ]; then shift; printf '%s' "$*"; else printf '%s\n' "$*"; fi
      }
      cd "$work" && eval "$lit_command"
    ) < /dev/null > "$work/lit.out" 2>&1
    lit_line_status=$?
    if [ "$lit_line_status" -eq 0 ] && [ ! -s "$work/lit.failed" ]; then
      say "RUN $lit_n: ok"
    else
      say "RUN $lit_n: failed: $lit_line"
      show "$work/lit.failed" "$work/lit.out"
    fi
  done < "$work/lit.lines"
  [ "$lit_n" -gt 0 ] || say "no RUN lines in ${1##*/}"
}

# native_step NAME CMD...: one step of native_pipeline.
native_step() {
  native_name=$1
  shift
  "$@" > "$work/native.log" 2>&1
  native_status=$?
  say "$native_name: exit $native_status"
  [ "$native_status" -eq 0 ] && return 0
  show "$work/native.log"
  return 1
}

# native_pipeline TOOLS LINKER SOURCE: lowers the MLIR text SOURCE to a
# native executable with the upstream tools in TOOLS (mlir-opt,
# mlir-translate, opt, llc) and LINKER, and checks each artifact. The status
# is 1 if a tool is missing or a step fails.
native_pipeline() {
  native_missing=
  for native_tool in mlir-opt mlir-translate opt llc; do
    [ -f "$1/$native_tool" ] || native_missing="$native_missing $native_tool"
  done
  [ -f "$2" ] || native_missing="$native_missing linker"
  if [ -n "$native_missing" ]; then
    say "missing:$native_missing"
    return 1
  fi
  say "tools: mlir-opt, mlir-translate, opt, llc and the linker"
  native=$work/native
  mkdir -p "$native"
  native_step mlir-opt "$1/mlir-opt" "$3" --convert-scf-to-cf --convert-to-llvm \
    --reconcile-unrealized-casts -o "$native/lowered.mlir" &&
  native_step mlir-translate "$1/mlir-translate" --mlir-to-llvmir "$native/lowered.mlir" \
    -o "$native/out.ll" &&
  native_step opt "$1/opt" -O2 -S "$native/out.ll" -o "$native/opt.ll" &&
  native_step llc "$1/llc" -O2 -filetype=obj --relocation-model=pic "$native/opt.ll" \
    -o "$native/out.o" &&
  native_step link "$2" "$native/out.o" -o "$native/out" || return 1
  native_found=
  for native_artifact in lowered.mlir out.ll opt.ll out.o out; do
    if [ -s "$native/$native_artifact" ]; then native_found="$native_found $native_artifact"; fi
  done
  say "artifacts:$native_found"
  if grep -q 'llvm.func @main' "$native/lowered.mlir"; then
    say "lowered: defines llvm.func @main"
  else
    say "lowered: no llvm.func @main"
  fi
  if grep -q 'ret i32 42' "$native/opt.ll"; then
    say "optimized: returns 42"
  else
    say "optimized: does not return 42"
  fi
  run_program native "$native/out" /dev/null
  say "run: exit $ran"
  if printf 'module { invalid syntax }' | "$1/mlir-opt" > /dev/null 2>&1; then
    say "mlir-opt: accepts invalid input"
  else
    say "mlir-opt: rejects invalid input"
  fi
}
