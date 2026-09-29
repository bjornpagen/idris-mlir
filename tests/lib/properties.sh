# Properties of the compiler that hold whatever the program: each is
# checked over every e2e fixture that compiles, with one failure line per
# fixture that breaks it. A fixture that does not compile is left out: its
# own e2e test reports that.

# property_fixtures: every e2e fixture, one path per line, in order: the
# directories of tests/e2e/<version> with a run script.
property_fixtures() {
  for pf_fixture in "$root"/tests/e2e/*/*; do
    [ -f "$pf_fixture/run" ] && say "$pf_fixture"
  done
}

# property_each CHECK: CHECK on every fixture in turn, with
# $property_fixture the fixture, $property_label its name as
# e2e/<version>/<name> and $property_dir a directory of its own, removed
# after it. CHECK compiles the fixture with property_compile and reports
# each failure with property_fail.
property_each() {
  : > "$work/property.failed"
  property_compiled=0
  pe_n=0
  for property_fixture in $(property_fixtures); do
    pe_n=$((pe_n + 1))
    property_dir=$work/fixture-$pe_n
    property_label=e2e/${property_fixture#"$root/tests/e2e/"}
    "$1"
    # A failure's evidence is in $work/property.failed already, and the
    # prelude's programs dump megabytes.
    rm -rf "$property_dir"
  done
}

# property_compile [--directive D]...: the fixture, copied afresh into
# $property_dir (a semantics test's program generated there, as sem_case
# does), compiled with the directives. The status is 0 when it compiled;
# the exit status is in $compiled, the directory of the dumps (with
# --directive dump-mlir) in $property_dumps and the emitted module in
# $property_emitted.
property_compile() {
  rm -rf "$property_dir"
  mkdir -p "$property_dir"
  case ${property_fixture##*/} in
    prim-*)
      if ! "$runtests" --sem-program "${property_fixture##*/}" > "$property_dir/Prog.idr" 2> "$work/compile.err"; then
        : > "$work/compile.out"
        compiled=1
        return 1
      fi
      ;;
    *) copy_fixture "$property_fixture" "$property_dir" ;;
  esac
  if [ -f "$property_dir/Main.idr" ]; then
    pc_packages=
    if [ -f "$property_fixture/packages" ]; then
      for pc_package in $(cat "$property_fixture/packages"); do pc_packages="$pc_packages -p $pc_package"; done
    fi
    # shellcheck disable=SC2086 # the packages are words
    compile_program --io $pc_packages "$@" "$property_dir/Main.idr" prog
    property_dumps=$property_dir/build/exec/prog.dump
    property_emitted=$property_dir/build/exec/prog.mlir
  else
    compile_program --int "$@" "$property_dir/Prog.idr" "$property_dir/build/exec/Prog"
    property_dumps=$property_dir/build/exec/Prog.dump
    property_emitted=$(find "$property_dir/build/ttc" -type f -name Prog.mlir 2> /dev/null | sort | head -n 1)
  fi
  [ "$compiled" -eq 0 ] || return 1
  property_compiled=$((property_compiled + 1))
}

# property_fail TEXT [FILE]: one failure of the fixture, and the file that
# shows it.
property_fail() {
  say "$property_label: $1" >> "$work/property.failed"
  [ -z "${2-}" ] || show "$2" >> "$work/property.failed"
}

# property NAME: the property NAME, a check below whose name is NAME with
# dashes as underscores, over every fixture; then `NAME: holds`, or
# `NAME: fails` and every failure. A test of the pool is this one call.
property() {
  property_each "$(printf '%s' "$1" | tr - _)"
  if [ -s "$work/property.failed" ]; then
    say "$1: fails"
    cat "$work/property.failed"
  elif [ "$property_compiled" -eq 0 ]; then
    say "$1: no fixture compiled"
  else
    say "$1: holds"
  fi
}

# property_dumped: the last compilation dumped modules, or a failure.
property_dumped() {
  [ -n "$(find "$property_dumps" -maxdepth 1 -type f -name '[0-9]*-*.mlir' 2> /dev/null | head -n 1)" ] &&
    return 0
  property_fail "no module was dumped"
  return 1
}

# dumps_verify: idris-mlir-opt parses every module the pipeline dumped
# after a step again, and its verifier accepts it.
dumps_verify() {
  property_compile --directive dump-mlir || return 0
  property_dumped || return 0
  for vd_dump in "$property_dumps"/[0-9]*-*.mlir; do
    bounded "$idris_mlir_opt" --mlir-disable-threading "$vd_dump" -o /dev/null > "$work/opt.log" 2>&1 ||
      property_fail "${vd_dump##*/} does not parse and verify" "$work/opt.log"
  done
}

# simplify_idempotent: idr-simplify, run again on each module it left, changes
# nothing: its first round leaves the module as it found it.
simplify_idempotent() {
  property_compile --directive dump-mlir || return 0
  property_dumped || return 0
  sa_found=
  for sa_dump in "$property_dumps"/[0-9]*-idr-simplify.mlir; do
    [ -f "$sa_dump" ] || continue
    sa_found=yes
    bounded "$idris_mlir_opt" --mlir-disable-threading "$sa_dump" --idr-simplify \
      --remarks-filter-passed=idr-simplify -o /dev/null > "$work/simplify.log" 2>&1
    sa_status=$?
    if [ "$sa_status" -ne 0 ]; then
      property_fail "idr-simplify on ${sa_dump##*/} exited $sa_status" "$work/simplify.log"
    elif ! grep -q 'round 1 changed nothing' "$work/simplify.log"; then
      property_fail "idr-simplify changed ${sa_dump##*/}, its own output" "$work/simplify.log"
    fi
  done
  [ -n "$sa_found" ] || property_fail "no module was dumped after idr-simplify"
}

# deterministic_dumps: two compilations emit the same module and dump the same
# modules after every step, byte for byte.
deterministic_dumps() {
  property_compile --directive dump-mlir || return 0
  property_dumped || return 0
  rm -rf "$work/first"
  mkdir "$work/first"
  cp "$property_dumps"/* "$work/first/"
  cp "$property_emitted" "$work/first/emitted"
  if ! property_compile --directive dump-mlir; then
    property_fail "compiled once, but not twice (exit $compiled)" "$work/compile.err"
    return 0
  fi
  cp "$property_emitted" "$property_dumps/emitted"
  sd_differ=
  for sd_name in $( (ls "$work/first"; ls "$property_dumps") | sort -u); do
    cmp -s "$work/first/$sd_name" "$property_dumps/$sd_name" || sd_differ="$sd_differ $sd_name"
  done
  [ -z "$sd_differ" ] || property_fail "differs between two compilations:$sd_differ"
}

# no_budget_error: no compilation, with evaluation or without, runs a
# compile-time budget out or is stopped by the step limit; either would say
# that an optimization is not finite.
no_budget_error() {
  property_compile
  budget_kept "with evaluation"
  property_compile --directive no-eval
  budget_kept "with --no-eval"
}

# quantities_kept: no step of the pipeline drops or widens a quantity Idris
# proved: after each step, up to lowering, where quantities end with the
# idr dialect, every parameter has its quantity, the one it has in the
# emitted module (idr-expect's quantities-kept).
quantities_kept() {
  property_compile --directive dump-mlir || return 0
  property_dumped || return 0
  for qk_dump in "$property_emitted" "$property_dumps"/[0-9]*-*.mlir; do
    case ${qk_dump##*/} in [0-9]*-idr-lower.mlir) break ;; esac
    expect_holds "$qk_dump" "quantities-kept=$property_emitted" ||
      property_fail "after ${qk_dump##*/}: quantities lost" "$work/expect.log"
  done
}

# budget_kept MODE: the last compilation kept within its budgets.
budget_kept() {
  if grep -qF 'compile-time budget' "$work/compile.out" "$work/compile.err"; then
    property_fail "$1: a compile-time budget ran out" "$work/compile.err"
  elif [ "$compiled" -eq 124 ]; then
    property_fail "$1: stopped after ${step_limit}s"
  fi
}
