# What holds of every compilation, checked on each e2e fixture's own
# compilation (lib/e2e.sh): the fixture is compiled once, with every module
# the pipeline passes through dumped, and the properties below read those
# dumps. Nothing compiles a fixture a second time: a compile is seconds, and
# there are hundreds of fixtures.

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
# end with the idr dialect, every parameter of an idr.func or an idr.lambda
# and every constructor field has the quantity, linear or unrestricted, it
# has in the emitted module (idr-expect's quantities-kept, which reads the
# binders' types). The emitted module holds no quantity zero: what Idris erased
# is no parameter. A binder is found by its source location, its names
# removed, so a step that renames or clones a function still meets it; the
# dumps print their locations.
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

