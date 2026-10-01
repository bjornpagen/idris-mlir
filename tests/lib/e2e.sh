# The end-to-end programs: compiled, run, and held to their oracles.
#
# Each fixture is compiled once with every module of the pipeline dumped,
# and everything that holds of a compilation is read off that one
# compilation and its dumps (lib/properties.sh); then once more without
# compile-time evaluation, whose program must behave the same. Two
# compilations per fixture, and no suite that compiles them all again.

# e2e_io FIXTURE: an IO program, Main.idr and its other modules, run on its
# stdin against its expected-stdout and expected-exit or expected-crash,
# with the checks of its modules (module_checks). The stock Chez
# backend compiles the same program, and must print the same stdout and
# exit with the same status (chez_agrees); with `oracle-chez` it is the only
# oracle of stdout, and with `no-chez`, which says why, it is not run.
# `packages` names installed packages it uses. It runs on a 1 MiB stack,
# or with `default-stack`, which says why, on the one programs get. With an
# Oracle.idr, stock Idris's evaluator is an oracle too: it proves
# `Prog.result = <literal>`, and that literal is the expected stdout.
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
  io_stack=small
  [ -f "$io_fixture/default-stack" ] && io_stack=
  io_directives=$(module_directives "$io_fixture")
  if [ -f "$io_fixture/Oracle.idr" ]; then
    check_oracle "$io_fixture"
    oracle_matches_stdout "$io_fixture"
  fi

  mkdir "$work/ours"
  copy_fixture "$io_fixture" "$work/ours"
  compile_program $io_packages $io_directives "$work/ours/Main.idr" prog
  say "compile: exit $compiled"
  if [ "$compiled" -ne 0 ]; then
    show "$work/compile.out" "$work/compile.err"
    return
  fi
  artifacts "$work/ours" prog.core prog.mlir prog.o prog
  run_ours ours "$work/ours/build/exec/prog" "$io_stdin" $io_stack
  ours_status=$ran

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

  object_imports "$work/ours/build/exec/prog.o" "$here"
  heap_free "$here" "$work/ours/build/exec/prog.dump"
  module_checks "$io_fixture" "$work/ours/build/exec/prog.mlir" "$work/ours/build/exec/prog.dump"
  compilation_properties "$work/ours/build/exec/prog.mlir" "$work/ours/build/exec/prog.dump"

  if [ -f "$io_fixture/no-chez" ]; then
    say "chez: not compared (no-chez)"
  else
    # shellcheck disable=SC2086 # the packages are words
    chez_agrees "$io_fixture" "$io_stdin" "$io_crash" "$ours_status" $io_packages
  fi
  without_evaluation "$io_fixture" "$io_stdin" $io_stack
}

# module_directives FIXTURE: the directives the fixture's compilation
# needs, one per line. Every compilation dumps the module after each step:
# the checks of the fixture's modules read the dumps, and so do the
# properties of every compilation (compilation_properties).
module_directives() {
  {
    say '--directive dump-mlir'
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
