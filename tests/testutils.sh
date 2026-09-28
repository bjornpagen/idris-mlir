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
#
# Every compilation's wall time is recorded under tests/build/timing, one
# file per test, with the module it emitted; tests/compile-times.sh lists
# the slowest. The record gates nothing.

idris_mlir=$1
root=${IDRIS_MLIR_ROOT:?IDRIS_MLIR_ROOT must name the repository}
# The pinned tools: $llvm_bin, $pinned_cc, $idris_mlir_cc, $idris_mlir_opt,
# and $idris2, stock Idris 2, the reference implementation (SEM-REF-1).
. "$root/tools/toolchain.sh"
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

# now_ms: the wall clock in milliseconds (GNU date's nanoseconds, or whole
# seconds where date has none).
now_ms() {
  now_ms_ns=$(date +%s%N)
  case $now_ms_ns in
    *N) say "$(( $(date +%s) * 1000 ))" ;;
    *) say "$(( now_ms_ns / 1000000 ))" ;;
  esac
}

# The timing record of this test: tests/build/timing/<test path, / as __>.tsv,
# one line per compilation, `<ms> TAB <exit> TAB <what> TAB <module>`, where
# <module> is the emitted .mlir kept next to it (or -), so that
# tests/compile-times.sh can run idris-mlir-cc --timing on it again.
timing_dir=$root/tests/build/timing
case $here in
  "$root/tests/"*) timing_id=$(printf '%s' "${here#"$root/tests/"}" | sed 's|/|__|g') ;;
  *) timing_id=$(printf '%s' "$here" | sed 's|^/||; s|/|__|g') ;;
esac
timing_count=0

# record_time MS COMPILE-ARGUMENTS...: one line of the timing record.
record_time() {
  record_ms=$1
  shift
  record_what=compile
  record_flow=
  while [ $# -gt 2 ]; do
    case $1 in
      --int | --io) record_flow=$1 ;;
      --directive) record_what="$record_what --directive $2"; shift ;;
      -p) shift ;;
    esac
    shift
  done
  record_source=$1
  record_output=$2
  mkdir -p "$timing_dir" 2> /dev/null || return 0
  if [ "$timing_count" -eq 0 ]; then
    : > "$timing_dir/$timing_id.tsv"
    rm -f "$timing_dir/$timing_id".*.mlir
  fi
  timing_count=$((timing_count + 1))
  record_module=-
  if [ "$compiled" -eq 0 ]; then
    record_dir=$(dirname "$record_source")
    if [ "$record_flow" = --io ]; then
      record_found=$record_dir/build/exec/${record_output##*/}.mlir
    else
      record_stem=${record_source##*/}
      record_found=$(find "$record_dir/build/ttc" -type f -name "${record_stem%.*}.mlir" 2> /dev/null | sort | head -n 1)
    fi
    if [ -n "$record_found" ] && [ -f "$record_found" ]; then
      record_module=$timing_dir/$timing_id.$timing_count.mlir
      cp "$record_found" "$record_module" 2> /dev/null || record_module=-
    fi
  fi
  printf '%s\t%s\t%s\t%s\n' "$record_ms" "$compiled" "$record_what" "$record_module" \
    >> "$timing_dir/$timing_id.tsv"
}

# compile_program [--int|--io] [-p PACKAGE]... [--directive D]... SOURCE OUTPUT:
# DRV-FLOW-1 or DRV-FLOW-2 through tools/compile.sh, the one copy of the
# chain. Its output is in $work/compile.out and $work/compile.err, its exit
# status in $compiled; its wall time goes to the timing record.
compile_program() {
  compile_started=$(now_ms)
  IDRIS_MLIR=$idris_mlir "$compile_sh" "$@" > "$work/compile.out" 2> "$work/compile.err"
  compiled=$?
  record_time "$(( $(now_ms) - compile_started ))" "$@"
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
    say "artifacts left after a rejection: $(printf '%s\n' "$no_artifacts_left" | tr '\n' ' ')"
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

# filecheck CHECKS INPUT: the pinned FileCheck. A line
# `// FILECHECK-OPTIONS: <option>...` in CHECKS adds options, words without
# quotes, such as --implicit-check-not=idr.closure (a check over the whole
# input).
filecheck() {
  filecheck_options=$(sed -n 's|^[[:space:]]*//[[:space:]]*FILECHECK-OPTIONS:[[:space:]]*||p' "$1" | tr '\n' ' ')
  set -f
  # shellcheck disable=SC2086 # the options are words
  "$llvm_bin/FileCheck" "$1" --input-file="$2" $filecheck_options > "$work/filecheck.log" 2>&1
  filecheck_status=$?
  set +f
  if [ "$filecheck_status" -eq 0 ]; then
    say "FileCheck ${1##*/}: ok"
  else
    say "FileCheck ${1##*/} on ${2##*/}: failed"
    show "$work/filecheck.log"
  fi
}

# rule: TEST-ELIM-1, TEST-EMIT-1, DRV-DUMP-1
# An mlir.check file is FileChecked against one module of the compilation.
# Its first line chooses which:
#
#     // input: emitted              the .mlir Emit wrote (TEST-EMIT-1)
#     // input: after <step>         the module after that step of
#                                    idris-mlir-cc's pipeline
#
# and without either, the module after `idr-simplify`, the simplify loop,
# where the eliminations of ELIM-* are done and nothing is lowered yet
# (TEST-ELIM-1). A step's module is the file `<NN>-<step>.mlir` that
# idris-mlir-cc --dump-after=all writes (DRV-DUMP-1), found by the step's
# name and not by its number, so it survives steps added before it; of two
# dumps of a step (canonicalize runs more than once) the first is taken. A
# step that left no dump fails the check, never falls back to another.

# mlir_input CHECK: `emitted`, or the step whose module CHECK reads.
mlir_input() {
  mlir_input_first=$(head -n 1 "$1")
  case $mlir_input_first in
    *'// input: emitted'*) say emitted ;;
    *'// input: after '*) say "${mlir_input_first##*// input: after }" | awk '{ print $1 }' ;;
    *) say idr-simplify ;;
  esac
}

# mlir_directives CHECK: the directives a compilation needs for CHECK.
mlir_directives() {
  [ -f "$1" ] || return 0
  [ "$(mlir_input "$1")" = emitted ] || say '--directive dump-mlir'
}

# check_mlir CHECK EMITTED DUMPS: FileCheck of CHECK on its input, the emitted
# module EMITTED or a module of the directory DUMPS.
check_mlir() {
  check_mlir_step=$(mlir_input "$1")
  if [ "$check_mlir_step" = emitted ]; then
    filecheck "$1" "$2"
    return
  fi
  check_mlir_file=$(find "$3" -maxdepth 1 -type f -name "[0-9]*-$check_mlir_step.mlir" 2> /dev/null | sort | head -n 1)
  if [ -z "$check_mlir_file" ]; then
    say "${1##*/}: no module dumped after $check_mlir_step"
    ls "$3" 2> /dev/null | sed 's/^/  | /'
    return
  fi
  filecheck "$1" "$check_mlir_file"
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

# compile_v0 DIR [--directive D]...: DRV-FLOW-1 on DIR/Prog.idr, to
# DIR/build/exec/Prog.
compile_v0() {
  compile_v0_dir=$1
  shift
  compile_program --int "$@" "$compile_v0_dir/Prog.idr" "$compile_v0_dir/build/exec/Prog"
  set -- "$compile_v0_dir"
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
  # shellcheck disable=SC2046 # the directives are words
  compile_v0 "$work/e2e" $(mlir_directives "$1/mlir.check") || return
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
    check_mlir "$1/mlir.check" "$(find "$work/e2e/build/ttc" -type f -name Prog.mlir | sort | head -n 1)" \
      "$work/e2e/build/exec/Prog.dump"
  fi
}

# rule: TEST-IO-1, TEST-DIFF-1, TEST-ELIM-1, SEM-DEV-1, DRV-FLOW-2, DRV-DUMP-1, FE-ENTRY-4
# e2e_io FIXTURE: an IO program, Main.idr and its other modules, run on its
# stdin against its expected-stdout and expected-exit or expected-crash,
# with its translate.check (on full Core, 01-translate.core) and mlir.check
# (see check_mlir). The stock Chez
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
  io_directives=$(mlir_directives "$io_fixture/mlir.check")
  if [ -f "$io_fixture/translate.check" ]; then
    io_directives="$io_directives --directive dump-core"
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
  [ -f "$io_fixture/translate.check" ] &&
    filecheck "$io_fixture/translate.check" "$work/ours/build/exec/prog.dump/01-translate.core"
  [ -f "$io_fixture/mlir.check" ] &&
    check_mlir "$io_fixture/mlir.check" "$work/ours/build/exec/prog.mlir" "$work/ours/build/exec/prog.dump"

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
    # SEM-DEV-1: crash messages are not compared, and Chez writes its own to
    # stdout: after this compiler's output, or as an `ERROR: ` line before
    # the Prelude's buffered output.
    io_bytes=$(wc -c < "$work/ours.out" | tr -d ' ')
    if head -c "$io_bytes" "$work/chez.out" | cmp -s - "$work/ours.out"; then
      tail -c +"$((io_bytes + 1))" "$work/chez.out" > "$work/chez.rest"
      if [ ! -s "$work/chez.rest" ] || [ "$(head -c 7 "$work/chez.rest")" = "ERROR: " ]; then
        io_same=yes
      fi
    fi
    if [ "$io_same" = no ] && sed '/^ERROR: /d' "$work/chez.out" | cmp -s - "$work/ours.out"; then
      io_same=yes
    fi
  fi
  # SEM-DEV-2: on the lines `libm-lines` names (one number per line), the
  # outputs are libm results, musl's here and the host's in Chez, which may
  # differ by one unit in the last place where libm is not correctly
  # rounded.
  if [ "$io_same" = no ] && [ -f "$io_fixture/libm-lines" ] &&
     awk -v lines="$io_fixture/libm-lines" '
       BEGIN { while ((getline n < lines) > 0) libm[n] = 1 }
       NR == FNR { ours[FNR] = $0; n1 = FNR; next }
       { n2 = FNR
         if ($0 == ours[FNR]) next
         if (!(FNR in libm)) exit 1
         a = ours[FNR] + 0; b = $0 + 0; m = (a < 0 ? -a : a); if ((b < 0 ? -b : b) > m) m = (b < 0 ? -b : b)
         d = a - b; if (d < 0) d = -d
         if (d > m * 2 ^ -52) exit 1 }
       END { if (n1 != n2) exit 1 }' "$work/ours.out" "$work/chez.out"; then
    io_same=libm
  fi
  if [ "$io_same" = libm ]; then
    if [ "$io_chez_status" -eq "$io_ours_status" ]; then
      say "chez: same stdout, up to one ulp on the libm lines (SEM-DEV-2), and exit status"
    else
      say "chez: same stdout up to one ulp, but Chez exited $io_chez_status and this compiler $io_ours_status"
    fi
  elif [ "$io_same" = no ]; then
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

# rejection_rule: the rule of a user error in the last compilation's
# output (`unsupported (<RULE>)`), or nothing.
rejection_rule() {
  cat "$work/compile.out" "$work/compile.err" | grep -o 'unsupported ([A-Z0-9-]*)' | head -n 1
}

# rule: SEM-EVAL-6, SEM-EVAL-7, ELIM-EVAL-1, OPT-SAFE-1
# equivalent FIXTURE: an e2e fixture (TEST-ORACLE-1, TEST-IO-1) compiled twice,
# with evaluation and with `--directive no-eval`, which leaves every closed
# call to runtime (docs/cutover.md 6.4): both executables must print the
# same stdout and exit with the same status on the fixture's stdin. Crash
# messages are not compared. A fixture that --no-eval rejects with a user
# error (a value the profile forbids at runtime, which only evaluation
# removes) is listed with the rule, not failed; the listing is the test's
# expected output.
equivalent() {
  eq_fixture=${1%/}
  eq_name=${eq_fixture##*/}
  eq_dir=$work/eq/$eq_name
  mkdir -p "$eq_dir/eval" "$eq_dir/noeval"
  eq_stdin=/dev/null
  eq_packages=
  if [ -f "$eq_fixture/Main.idr" ]; then
    eq_flow=io
    [ -f "$eq_fixture/stdin" ] && eq_stdin=$eq_fixture/stdin
    if [ -f "$eq_fixture/packages" ]; then
      for eq_package in $(cat "$eq_fixture/packages"); do eq_packages="$eq_packages -p $eq_package"; done
    fi
  else
    eq_flow=int
  fi
  for eq_mode in eval noeval; do
    case $eq_name in
      SEM-INT-*)
        if ! "$runtests" --sem-program "$eq_name" > "$eq_dir/$eq_mode/Prog.idr" 2> "$work/sem.err"; then
          say "$eq_name: no TEST-SEM-1 program"
          return
        fi
        ;;
      *) copy_fixture "$eq_fixture" "$eq_dir/$eq_mode" ;;
    esac
    eq_directives=
    [ "$eq_mode" = noeval ] && eq_directives='--directive no-eval'
    # shellcheck disable=SC2086 # the packages and directives are words
    if [ "$eq_flow" = io ]; then
      compile_program --io $eq_packages $eq_directives "$eq_dir/$eq_mode/Main.idr" prog
      eq_exe=$eq_dir/$eq_mode/build/exec/prog
    else
      compile_program --int $eq_directives "$eq_dir/$eq_mode/Prog.idr" "$eq_dir/$eq_mode/build/exec/Prog"
      eq_exe=$eq_dir/$eq_mode/build/exec/Prog
    fi
    if [ "$compiled" -ne 0 ]; then
      eq_rule=$(rejection_rule)
      if [ "$eq_mode" = noeval ] && [ "$compiled" -eq 1 ] && [ -n "$eq_rule" ]; then
        say "$eq_name: compiles only with evaluation: $eq_rule"
      else
        say "$eq_name: $eq_mode: compile exit $compiled"
        show "$work/compile.out" "$work/compile.err"
      fi
      return
    fi
    run_program "$eq_mode" "$eq_exe" "$eq_stdin" small
    eval "eq_status_$eq_mode=\$ran"
  done
  if ! cmp -s "$work/eval.out" "$work/noeval.out"; then
    say "$eq_name: stdout differs (< evaluation, > --no-eval)"
    diff "$work/eval.out" "$work/noeval.out" | head -n 20 | sed 's/^/  | /'
  elif [ "$eq_status_eval" -ne "$eq_status_noeval" ]; then
    say "$eq_name: same stdout, but exit $eq_status_eval with evaluation and $eq_status_noeval with --no-eval"
  else
    say "$eq_name: same stdout and exit status"
  fi
}

# equivalence VERSION [sem]: `equivalent` on every fixture of
# tests/e2e/VERSION, in order; with `sem`, on its TEST-SEM-1 fixtures
# (SEM-INT-*) alone, and without, on the others.
equivalence() {
  for eq_base in $(cd "$root/tests/e2e/$1" && ls | LC_ALL=C sort); do
    [ -d "$root/tests/e2e/$1/$eq_base" ] || continue
    case $eq_base in
      SEM-INT-*) [ "${2-}" = sem ] || continue ;;
      *) [ "${2-}" = sem ] && continue ;;
    esac
    equivalent "$root/tests/e2e/$1/$eq_base"
  done
}

# fuzz_run LABEL EXE: runs a program on empty stdin; a failure is a problem
# of the current check.
fuzz_run() {
  run_program "$1" "$2" /dev/null
  if [ "$ran" -ne 0 ] || [ -s "$work/$1.err" ]; then
    printf '%s\n' "$fuzz_seed: $1 exited $ran" >> "$work/fuzz.compiled"
    head -n 5 "$work/$1.err" | sed 's/^/  | /' >> "$work/fuzz.compiled"
    return 1
  fi
}

# fuzz_agree OUTPUT: every case's lines (d<n>, j<n>, r<n>, with or without
# L) print one value; the disagreements are problems.
fuzz_agree() {
  awk -v seed="$fuzz_seed" -v what="$2" '
    $1 ~ /^[djr]L?[0-9]+$/ {
      key = substr($1, 2); value = $0; sub(/^[^ ]* /, "", value)
      if ((key in seen) && seen[key] != value)
        printf "%s: %s: case %s: %s, but %s\n", seed, what, key, seen[key], value
      else seen[key] = value
    }' "$1" >> "$work/fuzz.agree"
}

# rule: SEM-REF-1, SEM-EVAL-6, ELIM-G-6, ELIM-EVAL-1, SEM-DBL-3, TEST-DIFF-1
# fuzz SEED: the fuzzer (tests/Fuzz.idr). For each part, `runtime` and
# `static`, its program of SEED is compiled with evaluation, with
# --directive no-eval (the runtime part only: the static part's values
# cannot exist at runtime) and by the stock Chez backend; each runs on empty
# stdin, exits 0 and writes nothing on stderr. Then:
#   - each case prints one value on all its lines: the folders' (d), the one
#     idr-eval or the runtime computes (j) and the runtime's (r);
#   - --no-eval prints what evaluation prints, byte for byte;
#   - Chez prints the same, but for the lines of cases through libm (L),
#     which C libraries may round differently (SEM-DBL-3).
# IDRIS_MLIR_FUZZ_CASES sets the cases of a program (default 30), and
# IDRIS_MLIR_FUZZ_ROUNDS=N adds N seeds, SEED + 1000, SEED + 2000, ...; the
# output is the same for any of them.
fuzz() {
  fuzz_cases=${IDRIS_MLIR_FUZZ_CASES:-30}
  fuzz_rounds=${IDRIS_MLIR_FUZZ_ROUNDS:-0}
  for fuzz_part in runtime static; do
    : > "$work/fuzz.compiled"
    : > "$work/fuzz.agree"
    : > "$work/fuzz.noeval"
    : > "$work/fuzz.chez"
    fuzz_round=0
    while [ "$fuzz_round" -le "$fuzz_rounds" ]; do
      fuzz_seed=$(( $1 + 1000 * fuzz_round ))
      fuzz_round=$((fuzz_round + 1))
      fuzz_dir=$work/fuzz-$fuzz_part-$fuzz_seed
      mkdir -p "$fuzz_dir/eval" "$fuzz_dir/noeval" "$fuzz_dir/chez"
      if ! "$runtests" --fuzz-program "$fuzz_seed" "$fuzz_cases" "$fuzz_part" > "$fuzz_dir/Main.idr"; then
        printf '%s\n' "$fuzz_seed: no program" >> "$work/fuzz.compiled"
        continue
      fi
      fuzz_modes='eval chez'
      [ "$fuzz_part" = runtime ] && fuzz_modes='eval noeval chez'
      fuzz_ok=yes
      for fuzz_mode in $fuzz_modes; do
        cp "$fuzz_dir/Main.idr" "$fuzz_dir/$fuzz_mode/Main.idr"
        case $fuzz_mode in
          eval) compile_program --io "$fuzz_dir/eval/Main.idr" prog ;;
          noeval) compile_program --io --directive no-eval "$fuzz_dir/noeval/Main.idr" prog ;;
          chez)
            (cd "$fuzz_dir/chez" && $bounded "$idris2" --no-banner --no-color --no-prelude \
               --cg chez -o prog Main.idr) > "$work/compile.out" 2> "$work/compile.err"
            compiled=$?
            ;;
        esac
        if [ "$compiled" -ne 0 ]; then
          printf '%s\n' "$fuzz_seed: $fuzz_mode: compile exit $compiled" >> "$work/fuzz.compiled"
          cat "$work/compile.out" "$work/compile.err" | head -n 10 | sed 's/^/  | /' >> "$work/fuzz.compiled"
          fuzz_ok=no
          continue
        fi
        fuzz_run "$fuzz_mode" "$fuzz_dir/$fuzz_mode/build/exec/prog" || fuzz_ok=no
      done
      [ "$fuzz_ok" = yes ] || continue
      fuzz_agree "$work/eval.out" "with evaluation"
      if [ "$fuzz_part" = runtime ]; then
        fuzz_agree "$work/noeval.out" "with --no-eval"
        if ! cmp -s "$work/eval.out" "$work/noeval.out"; then
          printf '%s\n' "$fuzz_seed: (< evaluation, > --no-eval)" >> "$work/fuzz.noeval"
          diff "$work/eval.out" "$work/noeval.out" | head -n 10 | sed 's/^/  | /' >> "$work/fuzz.noeval"
        fi
      fi
      grep -v '^[djr]L' "$work/eval.out" > "$work/eval.host-independent"
      grep -v '^[djr]L' "$work/chez.out" > "$work/chez.host-independent"
      if ! cmp -s "$work/eval.host-independent" "$work/chez.host-independent"; then
        printf '%s\n' "$fuzz_seed: (< this compiler, > Chez)" >> "$work/fuzz.chez"
        diff "$work/eval.host-independent" "$work/chez.host-independent" | head -n 10 | sed 's/^/  | /' >> "$work/fuzz.chez"
      fi
    done
    fuzz_report "$fuzz_part: every build compiles, runs, exits 0 and writes nothing on stderr" fuzz.compiled
    fuzz_report "$fuzz_part: each case prints one value, whoever computes it" fuzz.agree
    [ "$fuzz_part" = runtime ] &&
      fuzz_report "$fuzz_part: --no-eval prints what evaluation prints" fuzz.noeval
    fuzz_report "$fuzz_part: Chez prints the same, the libm lines aside" fuzz.chez
  done
}

# fuzz_report TEXT FILE: TEXT, then `ok`, or `failed` and FILE's problems.
fuzz_report() {
  if [ -s "$work/$2" ]; then
    say "$1: failed"
    head -n 40 "$work/$2"
  else
    say "$1: ok"
  fi
}

# rule: SEM-REF-1, SEM-DBL-3, SEM-STR-2, FE-IN-3
# two_levels CORPUS...: the two-level test (tests/TwoLevels.idr). The helper
# tests/twolevels, Idris's own evaluator as a backend of the stock driver, is
# built; for each corpus, `primitives` or `prelude`, its terms are
# normalised by it (the upper level), and compiled by this compiler (the
# lower level) and by Chez, each run on empty stdin. The lower level prints
# Idris's value for every term but those Idris does not reduce, those whose
# value depends on the host by design (`-- host-dependent:` in Terms.idr),
# and those the pinned Idris evaluates differently from its own backends
# (`-- idris-differs:`), all of which are listed; and Chez prints what the
# lower level prints, the host-dependent terms aside.
two_levels() {
  (cd "$root/tests/twolevels" && $bounded "$idris2" --no-banner --no-color \
     --build-dir "$work/twolevels-build" --build twolevels.ipkg) > "$work/twolevels.log" 2>&1
  tl_built=$?
  tl_helper=$work/twolevels-build/exec/twolevels
  if [ "$tl_built" -ne 0 ] || [ ! -x "$tl_helper" ]; then
    say "helper: build exit $tl_built"
    show "$work/twolevels.log"
    return
  fi
  say "helper: built"
  for tl_corpus; do
    tl_dir=$work/tl-$tl_corpus
    mkdir -p "$tl_dir/upper" "$tl_dir/lower" "$tl_dir/chez"
    for tl_side in upper lower chez; do
      "$runtests" --two-levels-program "$tl_corpus" terms > "$tl_dir/$tl_side/Terms.idr" &&
        "$runtests" --two-levels-program "$tl_corpus" main > "$tl_dir/$tl_side/Main.idr" || {
          say "$tl_corpus: no program"
          continue 2
        }
    done
    (cd "$tl_dir/upper" && $bounded "$tl_helper" --no-banner --no-color --no-prelude --cg twolevels \
       -o unused Main.idr) > "$work/upper.out" 2> "$work/upper.err"
    say "$tl_corpus: Idris's evaluator: exit $?"
    [ -s "$work/upper.err" ] && show "$work/upper.err"
    compile_program --io "$tl_dir/lower/Main.idr" prog
    say "$tl_corpus: compile: exit $compiled"
    if [ "$compiled" -ne 0 ]; then
      show "$work/compile.out" "$work/compile.err"
      continue
    fi
    run_program lower "$tl_dir/lower/build/exec/prog" /dev/null
    say "$tl_corpus: run: exit $ran"
    empty "$tl_corpus: stderr" "$work/lower.err"
    (cd "$tl_dir/chez" && $bounded "$idris2" --no-banner --no-color --no-prelude --cg chez \
       -o prog Main.idr) > "$work/chez.log" 2>&1
    say "$tl_corpus: chez: compile exit $?"
    run_program chez "$tl_dir/chez/build/exec/prog" /dev/null
    # The terms not compared with Idris's value, and why.
    sed -n 's/^-- host-dependent: \(t[0-9]*\) \(.*\)$/\1 host-dependent: \2/p' "$tl_dir/lower/Terms.idr" > "$work/tl.host"
    sed -n 's/^-- idris-differs: \(t[0-9]*\) \(.*\)$/\1 Idris evaluates it differently: \2/p' "$tl_dir/lower/Terms.idr" > "$work/tl.differs"
    awk '$2 == "stuck" { print $1 " not reduced by Idris" }' "$work/upper.out" > "$work/tl.stuck"
    cat "$work/tl.host" "$work/tl.differs" "$work/tl.stuck" | sort -t t -k 2 -n > "$work/tl.skipped"
    while IFS= read -r tl_skip; do
      tl_term=${tl_skip%% *}
      tl_text=$(sed -n "s/^$tl_term = //p" "$tl_dir/lower/Terms.idr")
      say "$tl_corpus: not compared with Idris: $tl_skip: $tl_text"
    done < "$work/tl.skipped"
    # Line by line: t<n> <value>.
    awk 'FILENAME == ARGV[1] { skip[$1] = 1; next }
         FILENAME == ARGV[2] { upper[$1] = $0; next }
         !($1 in skip) && upper[$1] != $0 { printf "  | %s: Idris: %s; this compiler: %s\n", $1, upper[$1], $0 }
        ' "$work/tl.skipped" "$work/upper.out" "$work/lower.out" > "$work/tl.diff"
    tl_upper_terms=$(wc -l < "$work/upper.out" | tr -d ' ')
    tl_lower_terms=$(wc -l < "$work/lower.out" | tr -d ' ')
    if [ -s "$work/tl.diff" ] || [ "$tl_upper_terms" -ne "$tl_lower_terms" ]; then
      say "$tl_corpus: this compiler prints Idris's value for every other term: failed ($tl_upper_terms against $tl_lower_terms lines)"
      head -n 40 "$work/tl.diff"
    else
      say "$tl_corpus: this compiler prints Idris's value for every other term"
    fi
    for tl_side in lower chez; do
      awk 'FILENAME == ARGV[1] { host[$1] = 1; next } !($1 in host)' \
        "$work/tl.host" "$work/$tl_side.out" > "$work/$tl_side.host-independent"
    done
    if cmp -s "$work/lower.host-independent" "$work/chez.host-independent"; then
      say "$tl_corpus: Chez prints the same, the host-dependent terms aside"
    else
      say "$tl_corpus: Chez prints differently (< this compiler, > Chez)"
      diff "$work/lower.host-independent" "$work/chez.host-independent" | head -n 20 | sed 's/^/  | /'
    fi
  done
}

# idris_lex MODE FILE: an Idris source file, lexed well enough to tell code
# from comments, strings and characters. MODE `code` prints each line of
# code, numbered as `<n>:<text>`, with comments removed (`--` to the end of
# the line, `|||` documentation, nested `{- -}` blocks), every string
# literal replaced by "" and every character literal by 'c'. MODE `strings`
# prints each string literal as `<n>:<contents>`, escapes as written.
idris_lex() {
  awk -v mode="$1" '
    BEGIN { depth = 0 }
    {
      line = $0; out = ""; n = length(line); i = 1
      while (i <= n) {
        c = substr(line, i, 1); two = substr(line, i, 2)
        if (depth > 0) {
          if (two == "{-") { depth++; i += 2; continue }
          if (two == "-}") { depth--; i += 2; continue }
          i++; continue
        }
        if (two == "{-") { depth = 1; i += 2; continue }
        if (two == "--" && (i == 1 || substr(line, i - 1, 1) !~ /[!#$%&*+.\/<=>?@\\^|~:-]/) &&
            substr(line, i + 2, 1) !~ /[!#$%&*+.\/<=>?@\\^|~:]/) break
        if (substr(line, i, 3) == "|||") break
        if (c == "\"") {
          s = ""; i++
          while (i <= n) {
            d = substr(line, i, 1)
            if (d == "\\") { s = s substr(line, i, 2); i += 2; continue }
            if (d == "\"") { i++; break }
            s = s d; i++
          }
          if (mode == "strings") print NR ":" s
          out = out "\"\""
          continue
        }
        if (c == "'"'"'" && (i == 1 || substr(line, i - 1, 1) !~ /[A-Za-z0-9_]/)) {
          j = i + 1
          if (substr(line, j, 1) == "\\") { j++; while (j <= n && substr(line, j, 1) != "'"'"'") j++ }
          else j++
          if (substr(line, j, 1) == "'"'"'") { out = out "'"'"'c'"'"'"; i = j + 1; continue }
        }
        out = out c; i++
      }
      if (mode == "code" && out ~ /[^ \t]/) print NR ":" out
    }' "$2"
}
