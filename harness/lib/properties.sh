# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# What holds of every compilation, checked on each e2e fixture's own
# compilation (lib/e2e.sh): the fixture is compiled once, with every module
# the pipeline passes through dumped, and the properties below read those
# dumps. Nothing compiles a fixture a second time: a compile is seconds, and
# there are hundreds of fixtures. universal prints them as one line.

# compilation_properties EMITTED DUMPS: the properties of the compilation
# that just ran (compile_program), whose emitted module is EMITTED and whose
# dumps are in DUMPS: every module dumped after a step parses and verifies
# again; no step up to lowering drops or widens a quantity Idris proved.
# Its status is 1 when one fails.
compilation_properties() {
  if [ -z "$(step_dumps "$2" | head -n 1)" ]; then
    say "dumps: none"
    return 1
  fi
  cp_failed=
  dumps_verify "$2" || cp_failed=yes
  quantities_kept "$1" "$2" || cp_failed=yes
  [ -z "$cp_failed" ]
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
  [ -z "$dv_failed" ] || return 1
  say "dumps: parse and verify"
}

# quantities_kept EMITTED DUMPS: no step of the pipeline drops or widens a
# quantity Idris proved: after each step, up to lowering, where quantities
# end with the idr dialect, every parameter of an idr.func and every
# constructor field has the quantity, linear or unrestricted, it has in the
# emitted module (idr-expect's quantities-kept, which reads the binders'
# types). The emitted module holds no quantity zero: what Idris erased is
# no parameter. A binder is found by its source location, the name the
# frontend gave it over its definition's span, so a step that clones a
# function still meets it; the dumps print their locations. The steps
# checked end at the dump of idr-lower, which must be among them: without
# it the steps up to lowering are not known, and the check fails rather
# than run over lowered modules, where it would hold of nothing.
quantities_kept() {
  qk_failed=
  qk_lowered=
  for qk_dump in "$1" $(step_dumps "$2"); do
    if [ "$(step_of "$qk_dump")" = idr-lower ]; then
      qk_lowered=yes
      break
    fi
    if ! expect_holds "$qk_dump" "quantities-kept=$1"; then
      say "quantities: lost after ${qk_dump##*/}"
      show "$work/expect.log"
      qk_failed=yes
    fi
  done
  if [ -z "$qk_lowered" ]; then
    say "quantities: no module dumped after idr-lower, so no step is known to come before lowering"
    return 1
  fi
  [ -z "$qk_failed" ] || return 1
  say "quantities: kept"
}

# universal EMITTED DUMPS OBJECT...: what holds of every compilation, as
# one line: the objects OBJECT... import nothing a program may not
# (object_imports), and the compilation whose emitted module is EMITTED
# and whose dumps are in DUMPS keeps its properties
# (compilation_properties). One line, `universal: holds`, when all hold;
# otherwise the lines of the checks, and status 1. A check added to every
# compilation is added here, and no transcript changes.
universal() {
  universal_emitted=$1
  universal_dumps=$2
  shift 2
  universal_failed=
  object_imports "$@" > "$work/universal.log" || universal_failed=yes
  compilation_properties "$universal_emitted" "$universal_dumps" >> "$work/universal.log" || universal_failed=yes
  if [ -n "$universal_failed" ]; then
    cat "$work/universal.log"
    return 1
  fi
  say "universal: holds"
}
