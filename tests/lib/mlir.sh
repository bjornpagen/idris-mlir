# FileCheck, and the module of a compilation an mlir.check reads.

# filecheck CHECKS INPUT: the pinned FileCheck. A line
# `// FILECHECK-OPTIONS: <option>...` in CHECKS adds options, words without
# quotes, such as --implicit-check-not={{[^#]}}idr.closure (a check over the
# whole input; the pattern leaves out `#idr.closure` attributes, which clone
# keys hold).
filecheck() {
  filecheck_options=$(sed -n 's|^[[:space:]]*//[[:space:]]*FILECHECK-OPTIONS:[[:space:]]*||p' "$1" | tr '\n' ' ')
  set -f
  # shellcheck disable=SC2086 # the options are words
  bounded "$llvm_bin/FileCheck" "$1" --input-file="$2" $filecheck_options > "$work/filecheck.log" 2>&1
  filecheck_status=$?
  set +f
  if [ "$filecheck_status" -eq 0 ]; then
    say "FileCheck ${1##*/}: ok"
  else
    say "FileCheck ${1##*/} on ${2##*/}: failed"
    show "$work/filecheck.log"
  fi
}

# An mlir.check file is FileChecked against one module of the compilation.
# Its first line chooses which:
#
#     // input: emitted              the .mlir Emit wrote
#     // input: after <step>         the module after that step of
#                                    idris-mlir-cc's pipeline
#
# and without either, the module after `idr-simplify`, the simplify loop,
# where the eliminations are done and nothing is lowered yet. A step's
# module is the file `<NN>-<step>.mlir` that idris-mlir-cc
# --dump-after=all writes, found by the step's
# name and not by its number, so it survives steps added before it; of two
# dumps of a step (canonicalize runs more than once) the first is taken. A
# step that left no dump fails the check, never falls back to another.

# mlir_input CHECK: `emitted`, or the step whose module CHECK reads.
mlir_input() {
  mlir_input_first=$(head -n 1 "$1")
  case $mlir_input_first in
    *'// input: emitted'*) say emitted ;;
    *'// input: after '*) say "${mlir_input_first##*// input: after }" | awk '{ print $1 }' ;;
    *) say idr-simplify ;;
  esac
}

# mlir_directives CHECK: the directives a compilation needs for CHECK.
mlir_directives() {
  [ -f "$1" ] || return 0
  [ "$(mlir_input "$1")" = emitted ] || say '--directive dump-mlir'
}

# check_mlir CHECK EMITTED DUMPS: FileCheck of CHECK on its input, the emitted
# module EMITTED or a module of the directory DUMPS.
check_mlir() {
  check_mlir_step=$(mlir_input "$1")
  if [ "$check_mlir_step" = emitted ]; then
    filecheck "$1" "$2"
    return
  fi
  check_mlir_file=$(find "$3" -maxdepth 1 -type f -name "[0-9]*-$check_mlir_step.mlir" 2> /dev/null | sort | head -n 1)
  if [ -z "$check_mlir_file" ]; then
    say "${1##*/}: no module dumped after $check_mlir_step"
    ls "$3" 2> /dev/null | sed 's/^/  | /'
    return
  fi
  filecheck "$1" "$check_mlir_file"
}
