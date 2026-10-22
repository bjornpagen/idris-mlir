# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# Compiling a program with the compiler under test, and the artifacts a
# compilation leaves or must not leave; and building a C++ program over the
# pinned MLIR, for an upstream check.

# compile_program [OPTION]... SOURCE OUTPUT: SOURCE, an IO program,
# compiled with idris-mlir's OPTION... (-p PACKAGE, --num-threads=N, the
# checks --idr-contracts and --idr-expect-at) through tools/compile.sh, the one copy of
# how idris-mlir runs. Its output is in $work/compile.out and
# $work/compile.err, its exit status in $compiled; its wall time goes to
# the timing record.
compile_program() {
  compile_started=$(now_ms)
  bounded "$compile_sh" "$@" > "$work/compile.out" 2> "$work/compile.err"
  compiled=$?
  record_time "$(( $(now_ms) - compile_started ))" "$@"
}

# The checked runtime, which every program a test runs links: a cell that
# dies keeps its memory marked and is never reused, so a release of a dead
# cell ends the run at the release, and a run that returns from main with a
# cell still live ends as the runtime's internal error naming the count.
# The runtime shipped programs link counts nothing.
checked_runtime=$dev_prefix/runtime/libidris_rt_checked.a

# compile_checked [OPTION]... SOURCE OUTPUT: compile_program, the program
# linked with the checked runtime.
compile_checked() {
  compile_program "--runtime=$checked_runtime" "$@"
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

# mlir_program SOURCE OUTPUT: SOURCE, a C++ program that calls the pinned
# LLVM and MLIR as libraries (an upstream check that reaches code no tool
# reaches alone: a walk mlir-opt's own parser would overflow first), built
# for the toolchain's target, as its toolchain file names it, with the
# flags those libraries were built with, and linked statically with every
# MLIR and LLVM archive of the toolchain, of which the linker takes what
# the program uses. The compiler's output is in $work/cc.log; status 0
# when built.
mlir_program() {
  mlir_program_triple=$(sed -n 's/^set(CMAKE_CXX_COMPILER_TARGET "\(.*\)")$/\1/p' "$llvm_prefix/toolchain.cmake" 2> /dev/null)
  mlir_program_config=$llvm_bin/llvm-config
  # shellcheck disable=SC2046 # llvm-config prints words
  bounded "$llvm_bin/clang++" --target="$mlir_program_triple" -O1 -DNDEBUG $("$mlir_program_config" --cxxflags) \
    "$1" -o "$2" "$llvm_prefix"/lib/libMLIR*.a \
    $("$mlir_program_config" --ldflags --link-static --libs --system-libs) > "$work/cc.log" 2>&1
}

# mlir_check WHAT SOURCE ARG...: SOURCE built by mlir_program and run with
# ARG...; one line, WHAT, when it exits 0 having printed `ok` alone, which
# is how such a program says each of its checks held; otherwise its build
# log, or its status and what it printed.
mlir_check() {
  mlir_check_what=$1
  mlir_check_program=$work/${2##*/}
  mlir_check_program=${mlir_check_program%.cpp}
  if ! mlir_program "$2" "$mlir_check_program"; then
    say "${mlir_check_program##*/}: does not build"
    show "$work/cc.log"
    return
  fi
  shift 2
  bounded "$mlir_check_program" "$@" > "$work/mlir-check.out" 2> "$work/mlir-check.err"
  mlir_check_status=$?
  if [ "$mlir_check_status" -eq 0 ] && [ "$(cat "$work/mlir-check.out")" = ok ]; then
    say "$mlir_check_what"
  else
    say "${mlir_check_program##*/}: exit $mlir_check_status, so not: $mlir_check_what"
    show "$work/mlir-check.out" "$work/mlir-check.err"
  fi
}

# The artifacts a build leaves in build/exec, by kind, held here once:
# every check of what a compilation leaves, keeps or compares reads them
# through artifact_patterns. A build named NAME leaves its Core, the module
# the frontend hands the driver (bytecode, which every tool reads by its
# magic), the objects code generation writes, one per bin, each <bin>.o in
# the directory NAME.objects, and the executable.
artifact_kinds='core module objects executable'

# artifact_patterns KIND NAME: the paths of KIND for the build NAME, as
# find's -path patterns, one per line.
artifact_patterns() {
  case $1 in
    core) say "*/$2.core" ;;
    module) say "*/$2.mlirbc" ;;
    objects) say "*/$2.objects/*.o" ;;
    executable) say "*/$2" ;;
  esac
}

# artifact_files DIR NAME KIND: the files of KIND that the build NAME left
# under DIR/build, sorted, one per line.
artifact_files() {
  artifact_patterns "$3" "$2" | while IFS= read -r artifact_pattern; do
    find "$1/build" -type f -path "$artifact_pattern" 2> /dev/null
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
