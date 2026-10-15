# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# Properties of a module stated by name, as idr-expect checks them (each is
# declared, with what it states, in idr/Transforms/Expect.h): what a test
# says instead of matching the ops that happen to show a property.

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

# An mlir.expect file lists, one line each, `<step>: <property>...`: the
# properties that hold of the module after that top-level pass of
# idris-mlir's pipeline (lib/mlir.sh, step_module), or of the module the
# frontend handed the driver for the step `emitted`. Lines that start with
# `#` explain.

# check_expect FILE EMITTED DUMPS: every line of the mlir.expect FILE holds
# of its step's module (step_module); one line, `mlir.expect: holds`, or a
# line and idr-expect's errors for each step where some property fails.
check_expect() {
  check_expect_failed=
  while IFS= read -r check_expect_line; do
    case $check_expect_line in '#'* | '') continue ;; esac
    check_expect_step=${check_expect_line%%:*}
    if ! check_expect_module=$(step_module "$check_expect_step" "$2" "$3"); then
      say "mlir.expect: no module dumped after $check_expect_step"
      check_expect_failed=yes
      continue
    fi
    # shellcheck disable=SC2086 # the properties are words
    if ! expect_holds "$check_expect_module" ${check_expect_line#*:}; then
      say "mlir.expect: $check_expect_step: fails"
      show "$work/expect.log"
      check_expect_failed=yes
    fi
  done < "$1"
  [ -n "$check_expect_failed" ] || say "mlir.expect: holds"
}
