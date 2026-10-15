# What holds of every compilation, checked on each e2e fixture's own
# compilation (lib/e2e.sh): the fixture is compiled once, with every module
# the pipeline passes through dumped, and the properties below read those
# dumps. Nothing compiles a fixture a second time: a compile is seconds, and
# there are hundreds of fixtures.

# compilation_properties EMITTED DUMPS: the properties of the compilation
# that just ran (compile_program), whose emitted module is EMITTED and whose
# dumps are in DUMPS: every module dumped after a step parses and verifies
# again; no step up to lowering drops or widens a quantity Idris proved.
compilation_properties() {
  if [ -z "$(step_dumps "$2" | head -n 1)" ]; then
    say "dumps: none"
    return
  fi
  dumps_verify "$2"
  quantities_kept "$1" "$2"
}

# dumps_verify DUMPS: idris-mlir-opt parses every module the pipeline dumped
# after a step again, and its verifier accepts it.
dumps_verify() {
  dv_failed=
  for dv_dump in $(step_dumps "$1"); do
    if ! bounded "$idris_mlir_opt" --mlir-disable-threading "$dv_dump" -o /dev/null > "$work/opt.log" 2>&1; then
      say "dumps: ${dv_dump##*/} does not parse and verify"
      show "$work/opt.log"
      dv_failed=yes
    fi
  done
  [ -n "$dv_failed" ] || say "dumps: parse and verify"
}

# quantities_kept EMITTED DUMPS: no step of the pipeline drops or widens a
# quantity Idris proved: after each step, up to lowering, where quantities
# end with the idr dialect, every parameter of an idr.func and every
# constructor field has the quantity, linear or unrestricted, it has in the
# emitted module (idr-expect's quantities-kept, which reads the binders'
# types). The emitted module holds no quantity zero: what Idris erased is
# no parameter. A binder is found by its source location, the name the
# frontend gave it over its definition's span, so a step that clones a
# function still meets it; the dumps print their locations.
quantities_kept() {
  qk_failed=
  for qk_dump in "$1" $(step_dumps "$2"); do
    [ "$(step_of "$qk_dump")" = idr-lower ] && break
    if ! expect_holds "$qk_dump" "quantities-kept=$1"; then
      say "quantities: lost after ${qk_dump##*/}"
      show "$work/expect.log"
      qk_failed=yes
    fi
  done
  [ -n "$qk_failed" ] || say "quantities: kept"
}
