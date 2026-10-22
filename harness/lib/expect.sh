# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# Properties of a module stated by name, as idr-expect checks them (each is
# a row, with what it states, of idr-expect's table, generated from its
# records: its sentence says what it checks, and its argument is read into
# its shape before it runs): what a test says instead of matching the ops
# that happen to show a property.

# expect_holds MODULE PROPERTY...: every PROPERTY (`name` or
# `name=argument`) holds of MODULE; idr-expect's errors, one line for each
# place a property fails, are in $work/expect.log.
expect_holds() {
  expect_module=$1
  shift
  expect_list=$(printf '%s,' "$@")
  bounded "$idris_mlir_opt" --mlir-disable-threading "$expect_module" \
    "--idr-expect=holds=${expect_list%,}" -o /dev/null > "$work/expect.log" 2>&1
}

# A program test's properties of its modules are stated by stage: an
# mlir.expect file lists, one line each, `<stage>: <property>...`, the
# properties that hold of the program at that stage of the pipeline (the
# specification's stages, as the pipeline's table names them), checked in
# the compilation itself after every pass of the stage and as the program
# enters it, so a pass that breaks one fails naming the property, the
# stage and the pass. No line names a pass: a stage is what the pipeline's
# table defines, so a pass renamed, merged or split changes the table and
# no test. Lines that start with `#` explain. The mark `heap-free` is the
# property no-heap-allocation at the owned stage, the module that is
# lowered: the day an optimization stops keeping the program's values off
# the heap, the compilation fails.

# stage_options FIXTURE: the compilation's options for the properties
# FIXTURE states, `--idr-expect-at=<stage>:<property>,...` one per line;
# none when it states none.
stage_options() {
  [ -f "$1/heap-free" ] && say "--idr-expect-at=owned:no-heap-allocation"
  [ -f "$1/mlir.expect" ] || return 0
  while IFS= read -r so_line; do
    case $so_line in '#'* | '') continue ;; esac
    so_stage=${so_line%%:*}
    # shellcheck disable=SC2086 # the properties are words
    so_list=$(printf '%s,' ${so_line#*:})
    say "--idr-expect-at=$so_stage:${so_list%,}"
  done < "$1/mlir.expect"
}
