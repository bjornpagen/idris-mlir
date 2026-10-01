# What holds of every compilation, checked on each e2e fixture's own
# compilation (lib/e2e.sh): the fixture is compiled once, with every module
# the pipeline passes through dumped, and the properties below read those
# dumps. The fixture is compiled a second time without compile-time
# evaluation, and that program must behave as the first
# (without_evaluation). Nothing compiles a fixture a third time: a compile
# is seconds, and there are hundreds of fixtures.

# compilation_properties EMITTED DUMPS: the properties of the compilation
# that just ran (compile_program), whose emitted module is EMITTED and whose
# dumps are in DUMPS: it kept within its budgets; every dumped module parses
# and verifies again; idr-simplify, run again on the module it left,
# changes nothing; no step up to lowering drops or widens a quantity Idris
# proved.
compilation_properties() {
  budget_kept budget
  if [ -z "$(find "$2" -maxdepth 1 -type f -name '[0-9]*-*.mlir' 2> /dev/null | head -n 1)" ]; then
    say "dumps: none"
    return
  fi
  dumps_verify "$2"
  simplify_idempotent "$2"
  quantities_kept "$1" "$2"
}

# budget_kept LABEL: the last compilation ran no compile-time budget out and
# was not stopped by the step limit; either would say that an optimization
# is not finite by construction.
budget_kept() {
  if grep -qF 'compile-time budget' "$work/compile.out" "$work/compile.err"; then
    say "$1: a compile-time budget ran out"
    show "$work/compile.err"
  elif [ "$compiled" -eq 124 ]; then
    say "$1: stopped after ${step_limit}s"
  else
    say "$1: kept"
  fi
}

# dumps_verify DUMPS: idris-mlir-opt parses every module the pipeline dumped
# after a step again, and its verifier accepts it.
dumps_verify() {
  dv_failed=
  for dv_dump in "$1"/[0-9]*-*.mlir; do
    if ! bounded "$idris_mlir_opt" --mlir-disable-threading "$dv_dump" -o /dev/null > "$work/opt.log" 2>&1; then
      say "dumps: ${dv_dump##*/} does not parse and verify"
      show "$work/opt.log"
      dv_failed=yes
    fi
  done
  [ -n "$dv_failed" ] || say "dumps: parse and verify"
}

# simplify_idempotent DUMPS: idr-simplify, run again on each module it left,
# changes nothing: its first round leaves the module as it found it.
simplify_idempotent() {
  si_found=
  si_failed=
  for si_dump in "$1"/[0-9]*-idr-simplify.mlir; do
    [ -f "$si_dump" ] || continue
    si_found=yes
    bounded "$idris_mlir_opt" --mlir-disable-threading "$si_dump" --idr-simplify \
      --remarks-filter-passed=idr-simplify -o /dev/null > "$work/simplify.log" 2>&1
    si_status=$?
    if [ "$si_status" -ne 0 ]; then
      say "simplify: idr-simplify on ${si_dump##*/} exited $si_status"
      show "$work/simplify.log"
      si_failed=yes
    elif ! grep -q 'round 1 changed nothing' "$work/simplify.log"; then
      say "simplify: changed ${si_dump##*/}, its own output"
      show "$work/simplify.log"
      si_failed=yes
    fi
  done
  if [ -z "$si_found" ]; then
    say "simplify: no module was dumped after idr-simplify"
  elif [ -z "$si_failed" ]; then
    say "simplify: idempotent"
  fi
}

# quantities_kept EMITTED DUMPS: no step of the pipeline drops or widens a
# quantity Idris proved: after each step, up to lowering, where quantities
# end with the idr dialect, every parameter and constructor field has the
# quantity it has in the emitted module (idr-expect's quantities-kept).
quantities_kept() {
  qk_failed=
  for qk_dump in "$1" "$2"/[0-9]*-*.mlir; do
    case ${qk_dump##*/} in [0-9]*-idr-lower.mlir) break ;; esac
    if ! expect_holds "$qk_dump" "quantities-kept=$1"; then
      say "quantities: lost after ${qk_dump##*/}"
      show "$work/expect.log"
      qk_failed=yes
    fi
  done
  [ -n "$qk_failed" ] || say "quantities: kept"
}

# without_evaluation FIXTURE STDIN STACK: the fixture compiled again
# with `--directive no-eval`, which leaves every closed call to runtime,
# must print the stdout and exit with the status the first compilation's
# program did (in $work/ours.out and $ours_status), within its budgets. A
# fixture that --no-eval rejects with a user error (a value the profile
# forbids at runtime, which only evaluation removes) says so with the
# reason instead. STACK is `small` or empty, as the first run had it.
without_evaluation() {
  mkdir "$work/noeval"
  copy_fixture "$1" "$work/noeval"
  # shellcheck disable=SC2086 # the packages are words
  compile_program $io_packages --directive no-eval "$work/noeval/Main.idr" prog
  we_exe=$work/noeval/build/exec/prog
  if [ "$compiled" -ne 0 ]; then
    we_reason=$(rejection_reason)
    if [ "$compiled" -eq 1 ] && [ -n "$we_reason" ]; then
      say "no-eval: compiles only with evaluation: $we_reason"
    else
      say "no-eval: compile exit $compiled"
      show "$work/compile.out" "$work/compile.err"
    fi
    return
  fi
  budget_kept "no-eval budget"
  run_ours noeval "$we_exe" "$2" ${3:+small}
  if ! cmp -s "$work/ours.out" "$work/noeval.out"; then
    say "no-eval: stdout differs (< evaluation, > --no-eval)"
    diff "$work/ours.out" "$work/noeval.out" | head -n 20 | sed 's/^/  | /'
  elif [ "$ran" -ne "$ours_status" ]; then
    say "no-eval: same stdout, but exit $ours_status with evaluation and $ran with --no-eval"
  else
    say "no-eval: same stdout and exit status"
  fi
}
