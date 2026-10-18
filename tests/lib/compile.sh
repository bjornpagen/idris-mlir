# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# Compiling a program with the compiler under test, and the artifacts a
# compilation leaves or must not leave.

# compile_program [OPTION]... SOURCE OUTPUT: SOURCE, an IO program,
# compiled with idris-mlir's OPTION... (-p PACKAGE, --num-threads=N, and
# the IR tree printer's --mlir-print-ir-after-all with
# --mlir-print-ir-tree-dir=DIR) through tools/compile.sh, the one copy of
# how idris-mlir runs. Its output is in $work/compile.out and
# $work/compile.err, its exit status in $compiled; its wall time goes to
# the timing record.
compile_program() {
  compile_started=$(now_ms)
  bounded "$compile_sh" "$@" > "$work/compile.out" 2> "$work/compile.err"
  compiled=$?
  record_time "$(( $(now_ms) - compile_started ))" "$@"
}

# runtime_c CMD ARG...: CMD with ARG... and then the flags a C or C++ source
# that includes idris_rt.h compiles with, one argument per line of the
# file the build writes beside its runtime (runtime/c-flags): the runtime's
# own include directory, then the one its generated ABI header is in. So no
# test spells where the build generates that header.
runtime_c() {
  if [ ! -f "$dev_prefix/runtime/c-flags" ]; then
    printf '%s\n' "no $dev_prefix/runtime/c-flags, which the build writes" >&2
    return 1
  fi
  while IFS= read -r runtime_c_flag; do
    set -- "$@" "$runtime_c_flag"
  done < "$dev_prefix/runtime/c-flags"
  "$@"
}

# link_program ARG...: the pinned C compiler with ARG... (sources or objects,
# the runtime, -o and any option), then what links a program for the
# target, one argument per line of idris-mlir --print-link-flags, as
# idris-mlir links one.
link_program() {
  link_program_flags=$("$idris_mlir" --print-link-flags) || return 1
  while IFS= read -r link_program_flag; do
    set -- "$@" "$link_program_flag"
  done << EOF
$link_program_flags
EOF
  bounded "$pinned_cc" "$@"
}

# The artifacts a build leaves in build/exec, by kind, held here once:
# every check of what a compilation leaves, keeps or compares reads them
# through artifact_patterns. A build named NAME leaves its Core, the module
# the frontend hands the driver (bytecode, which every tool reads by its
# magic), the objects code generation writes, one per bin, each named
# NAME.<bin>.o, and the executable.
artifact_kinds='core module objects executable'

# artifact_patterns KIND NAME: the file names of KIND for the build NAME,
# as find's -name patterns, one per line.
artifact_patterns() {
  case $1 in
    core) say "$2.core" ;;
    module) say "$2.mlirbc" ;;
    objects) say "$2.*.o" ;;
    executable) say "$2" ;;
  esac
}

# artifact_files DIR NAME KIND: the files of KIND that the build NAME left
# under DIR/build, sorted, one per line.
artifact_files() {
  artifact_patterns "$3" "$2" | while IFS= read -r artifact_pattern; do
    find "$1/build" -type f -name "$artifact_pattern" 2> /dev/null
  done | LC_ALL=C sort -u
}

# artifact_file DIR NAME KIND: the one file of KIND, or nothing.
artifact_file() {
  artifact_files "$1" "$2" "$3" | head -n 1
}

# artifacts DIR NAME: the build NAME left a non-empty file of every kind
# under DIR/build. The line names the kinds, so it states what a
# compilation leaves, not how the driver spells it.
artifacts() {
  artifacts_found=
  artifacts_missing=
  for artifacts_kind in $artifact_kinds; do
    artifacts_files=$(artifact_files "$1" "$2" "$artifacts_kind")
    artifacts_empty=$(printf '%s\n' "$artifacts_files" | while IFS= read -r f; do
      [ -n "$f" ] && [ ! -s "$f" ] && say "$f"; done)
    if [ -n "$artifacts_files" ] && [ -z "$artifacts_empty" ]; then
      artifacts_found="$artifacts_found $artifacts_kind"
    else
      artifacts_missing="$artifacts_missing $artifacts_kind"
    fi
  done
  say "artifacts:$artifacts_found"
  [ -z "$artifacts_missing" ] || say "missing or empty:$artifacts_missing"
}

# no_artifacts DIR: no Core, module or object of any build under DIR/build.
no_artifacts() {
  no_artifacts_left=$(for no_artifacts_kind in core module objects; do
      artifact_files "$1" '*' "$no_artifacts_kind"
    done | sed "s|^$1/||" | LC_ALL=C sort -u)
  if [ -z "$no_artifacts_left" ]; then
    say "artifacts: none"
  else
    say "artifacts left after a rejection: $(printf '%s\n' "$no_artifacts_left" | tr '\n' ' ')"
  fi
}
