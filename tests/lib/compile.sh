# Compiling a program with the compiler under test, and the artifacts a
# compilation leaves or must not leave.

# compile_program [-p PACKAGE]... [--directive D]... SOURCE OUTPUT: SOURCE,
# an IO program, compiled through tools/compile.sh, the one copy of the
# chain. Its output is in $work/compile.out and $work/compile.err, its exit
# status in $compiled; its wall time goes to the timing record.
compile_program() {
  compile_started=$(now_ms)
  bounded env "IDRIS_MLIR=$idris_mlir" "$compile_sh" "$@" > "$work/compile.out" 2> "$work/compile.err"
  compiled=$?
  record_time "$(( $(now_ms) - compile_started ))" "$@"
}

# artifacts DIR NAME...: every NAME is a non-empty file somewhere under
# DIR/build.
artifacts() {
  artifacts_dir=$1
  shift
  artifacts_found=
  artifacts_missing=
  for artifacts_name in "$@"; do
    if [ -n "$(find "$artifacts_dir/build" -type f -name "$artifacts_name" 2> /dev/null | head -n 1)" ] &&
       [ -z "$(find "$artifacts_dir/build" -type f -name "$artifacts_name" -size 0 2> /dev/null)" ]; then
      artifacts_found="$artifacts_found $artifacts_name"
    else
      artifacts_missing="$artifacts_missing $artifacts_name"
    fi
  done
  say "artifacts:$artifacts_found"
  [ -z "$artifacts_missing" ] || say "missing or empty:$artifacts_missing"
}

# no_artifacts DIR: no .core, .mlir or object file under DIR/build.
no_artifacts() {
  no_artifacts_left=$(find "$1/build" -type f \( -name '*.core' -o -name '*.mlir' -o -name '*.o' \) 2> /dev/null | sed "s|^$1/||" | sort)
  if [ -z "$no_artifacts_left" ]; then
    say "artifacts: none"
  else
    say "artifacts left after a rejection: $(printf '%s\n' "$no_artifacts_left" | tr '\n' ' ')"
  fi
}

# rejection_reason: the reason of a user error in the last compilation's
# output (`unsupported (<reason>)`), or nothing.
rejection_reason() {
  cat "$work/compile.out" "$work/compile.err" | grep -o 'unsupported ([a-z][a-z -]*)' | head -n 1
}
