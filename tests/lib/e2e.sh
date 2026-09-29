# The end-to-end programs: compiled, run, and held to their oracles.

# compile_v0 DIR [--directive D]...: the `main : Int` program DIR/Prog.idr, to
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

# e2e_v0 FIXTURE: a `main : Int` program, Prog.idr, whose exit status is
# its Oracle.idr's literal mod 256 or its expected-exit, or which crashes
# with its expected-crash.
e2e_v0() {
  v0_expected=
  if [ -f "$1/Oracle.idr" ]; then
    v0_expected=$(oracle_value "$1") || { say "$v0_expected"; return; }
    check_oracle "$1"
  fi
  mkdir "$work/e2e"
  copy_fixture "$1" "$work/e2e"
  # shellcheck disable=SC2046 # the directives are words
  compile_v0 "$work/e2e" $(module_directives "$1") || return
  run_ours prog "$work/e2e/build/exec/Prog" /dev/null small
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
  heap_free "$work/e2e/build/exec/Prog.o" "$here"
  module_checks "$1" "$(find "$work/e2e/build/ttc" -type f -name Prog.mlir | sort | head -n 1)" \
    "$work/e2e/build/exec/Prog.dump"
}

# e2e_io FIXTURE: an IO program, Main.idr and its other modules, run on its
# stdin against its expected-stdout and expected-exit or expected-crash,
# with the checks of its modules (module_checks). The stock Chez
# backend compiles the same program, and must print the same stdout and
# exit with the same status (chez_agrees); with `oracle-chez` it is the only
# oracle of stdout. `packages` names installed packages it uses.
e2e_io() {
  io_fixture=$(cd "$1" && pwd)
  io_stdin=/dev/null
  [ -f "$io_fixture/stdin" ] && io_stdin=$io_fixture/stdin
  io_expected_exit=0
  [ -f "$io_fixture/expected-exit" ] && io_expected_exit=$(first_word "$io_fixture/expected-exit")
  io_packages=
  if [ -f "$io_fixture/packages" ]; then
    for io_package in $(cat "$io_fixture/packages"); do io_packages="$io_packages -p $io_package"; done
  fi
  io_directives=$(module_directives "$io_fixture")
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
  run_ours ours "$work/ours/build/exec/prog" "$io_stdin" small
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

  heap_free "$work/ours/build/exec/prog.o" "$here"
  module_checks "$io_fixture" "$work/ours/build/exec/prog.mlir" "$work/ours/build/exec/prog.dump"

  # shellcheck disable=SC2086 # the packages are words
  chez_agrees "$io_fixture" "$io_stdin" "$io_crash" "$io_ours_status" $io_packages
}

# module_directives FIXTURE: the directives that the checks of the
# fixture's modules need, one per line.
module_directives() {
  {
    mlir_directives "$1/mlir.check"
    expect_directives "$1/mlir.expect"
    [ -f "$1/translate.check" ] && say '--directive dump-core'
  } | sort -u
}

# module_checks FIXTURE EMITTED DUMPS: every check of the compilation's
# modules that the fixture holds: translate.check, FileChecked on full Core
# (01-translate.core); mlir.check (check_mlir); mlir.expect (check_expect).
module_checks() {
  [ -f "$1/translate.check" ] && filecheck "$1/translate.check" "$3/01-translate.core"
  [ -f "$1/mlir.check" ] && check_mlir "$1/mlir.check" "$2" "$3"
  [ -f "$1/mlir.expect" ] && check_expect "$1/mlir.expect" "$2" "$3"
  return 0
}
