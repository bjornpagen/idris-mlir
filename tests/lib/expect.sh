# Properties of a module stated by name, as idr-expect checks them (its
# description in Passes.td lists them): what a test says instead of
# matching the ops that happen to show a property.

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
# properties that hold of the module after that step of idris-mlir-cc's
# pipeline, or of the module Emit wrote for the step `emitted`. Lines that
# start with `#` explain.

# expect_steps FILE: the steps an mlir.expect names.
expect_steps() {
  sed -n 's/^\([a-z0-9-]*\):.*/\1/p' "$1"
}

# expect_directives FILE: the directives a compilation needs for FILE.
expect_directives() {
  [ -f "$1" ] || return 0
  expect_steps "$1" | grep -qvx emitted && say '--directive dump-mlir'
  return 0
}

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
