# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# Skipped actions: a transform that is an action of MLIR's action framework
# only makes the code faster or smaller, and skipped it leaves valid IR
# (foreign/idr/include/idr/Support/Actions.h). So a program's module run
# through idris-mlir-opt's pipeline with any set of them skipped gives a
# program that holds every case its fixture names, as the compilation with
# none skipped does: the same output and exit status, and no cell live at
# exit. That is the compiler's own claim, no oracle outside the program. A
# cell put in a frame it outlives (a dangling pointer) shows as a case that
# changes when that cell is left on the heap. Every program here links the
# checked runtime (runtime/Alloc/Alloc.h), which ends it at the first
# count operation on a cell that died or on a stack cell whose frame has
# returned, so a double release or a dangling cell fails its case where it
# happens, whatever it would have printed.

# The sets skipped: none, every cell put in a frame, every cell reused,
# every call inlined, all three at once, and one drawn stack cell and one
# drawn reuse site alone (each the only one performed), from a seed the
# run draws from the clock, which a failure names and
# IDRIS_MLIR_ACTIONS_SEED replays.
actions_seed=${IDRIS_MLIR_ACTIONS_SEED:-$(date +%s)}
actions_drawn=$((actions_seed % 8))
actions_skipped="none idr-stack-cell-count=0 idr-reuse-site-count=0 idr-optimize-inline-count=0
idr-stack-cell-count=0,idr-reuse-site-count=0,idr-optimize-inline-count=0
idr-stack-cell-skip=$actions_drawn,idr-stack-cell-count=1
idr-reuse-site-skip=$actions_drawn,idr-reuse-site-count=1"

# skipped_actions FIXTURE: the program of FIXTURE (Main.idr and the
# packages its `packages` names) compiled once, its module then through
# idr-pipeline with each set of actions_skipped and through idris-mlir to
# an executable that links the checked runtime, each run on every case of
# FIXTURE (e2e_case). One line per set when every case holds, the set named
# without the drawn index; otherwise the cases that did not, under it.
skipped_actions() {
  sa_fixture=$1
  rm -rf "$work/sa"
  mkdir "$work/sa"
  copy_fixture "$sa_fixture" "$work/sa"
  # shellcheck disable=SC2046 # the packages are words
  compile_program $(package_options "$sa_fixture") "$work/sa/Main.idr" prog
  if [ "$compiled" -ne 0 ]; then
    say "compile: exit $compiled"
    show "$work/compile.out" "$work/compile.err"
    return
  fi
  mkdir -p "$work/ours/build/exec"
  for sa_set in $actions_skipped; do
    sa_name=$(printf '%s' "$sa_set" | sed 's/-skip=[0-9]*,/-skip=drawn,/')
    case $sa_set in
      none) sa_counter= ;;
      *) sa_counter=--mlir-debug-counter=$sa_set ;;
    esac
    rm -f "$work/ours/build/exec/prog"
    # shellcheck disable=SC2086 # no counter is no argument
    if ! bounded "$idris_mlir_opt" "$work/sa/build/exec/prog.mlirbc" $sa_counter \
      --idr-target --idr-pipeline -o "$work/sa/lowered.mlir" > "$work/sa.out" 2> "$work/sa.err" ||
      ! bounded "$idris_mlir" "$work/sa/lowered.mlir" \
        "--runtime=$dev_prefix/foreign/idr/idris_rt_checked.o" -o "$work/ours/build/exec/prog" \
        >> "$work/sa.out" 2>> "$work/sa.err"; then
      say "skipped $sa_name: does not compile"
      show "$work/sa.out" "$work/sa.err"
      continue
    fi
    : > "$work/sa.failed"
    for sa_case in "$sa_fixture"/cases/*/; do
      sa_case=${sa_case%/}
      e2e_case "$sa_case" "${sa_case##*/}" >> "$work/sa.failed"
    done
    if [ -s "$work/sa.failed" ]; then
      say "skipped $sa_name: cases differ (IDRIS_MLIR_ACTIONS_SEED=$actions_seed)"
      cat "$work/sa.failed"
    else
      say "skipped $sa_name: each case as expected"
    fi
  done
}
