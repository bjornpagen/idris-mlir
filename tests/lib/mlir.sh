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
#     // input: emitted              the .mlir Emit wrote, as MLIR prints it
#     // input: after <step>         the module after that step of
#                                    idris-mlir's pipeline
#
# and without either, the module after `idr-simplify`, the simplify loop,
# where the eliminations are done and nothing is lowered yet. A step is a
# pass of idris-mlir's own pipeline, or a nested group of passes named by
# the first pass that ran in it (`idr-vectorize` is the module after the
# group of function passes it begins, idr-narrow-lanes and the cleanups
# after it included). A step's module is the file `<NN>-<step>.mlir` that
# idris-mlir --dump-dir writes, found by the step's name and not by its
# number, so it survives steps added before it; of two dumps of a step
# (canonicalize runs more than once) the first is taken. A step that left
# no dump fails the check, never falls back to another.
#
# Emit writes each op in its dialect's syntax where the dialect's format
# allows and in the generic form elsewhere, and the dumps are printed with
# aliases and with the names the printer suggests; idris-mlir-opt parses
# the module a check reads and prints it again, every location and type
# written where it is used (no alias) and each op in its dialect's syntax.
# So a check states the module, the same however Emit or a dump spells it;
# an op under an idr.func prints without its `idr.` prefix.

# mlir_input CHECK: `emitted`, or the step whose module CHECK reads.
mlir_input() {
  mlir_input_first=$(head -n 1 "$1")
  case $mlir_input_first in
    *'// input: emitted'*) say emitted ;;
    *'// input: after '*) say "${mlir_input_first##*// input: after }" | awk '{ print $1 }' ;;
    *) say idr-simplify ;;
  esac
}

# step_module STEP EMITTED DUMPS: the module of STEP, `emitted` (EMITTED) or
# the first dump of that step in the directory DUMPS; nothing, and status
# 1, when that step left no dump.
step_module() {
  if [ "$1" = emitted ]; then
    say "$2"
    return
  fi
  step_module_file=$(find "$3" -maxdepth 1 -type f -name "[0-9]*-$1.mlir" 2> /dev/null | sort | head -n 1)
  [ -n "$step_module_file" ] && say "$step_module_file"
}

# check_mlir CHECK EMITTED DUMPS: FileCheck of CHECK on its input, the emitted
# module EMITTED or a module of the directory DUMPS.
check_mlir() {
  check_mlir_step=$(mlir_input "$1")
  if ! check_mlir_file=$(step_module "$check_mlir_step" "$2" "$3"); then
    say "${1##*/}: no module dumped after $check_mlir_step"
    ls "$3" 2> /dev/null | sed 's/^/  | /'
    return
  fi
  if ! bounded "$idris_mlir_opt" --mlir-disable-threading --mlir-print-debuginfo \
       --mlir-print-local-scope "$check_mlir_file" -o "$work/check-printed.mlir" \
       > "$work/print.log" 2>&1; then
    say "${1##*/}: the module of $check_mlir_step does not parse and verify"
    show "$work/print.log"
    return
  fi
  filecheck "$1" "$work/check-printed.mlir"
}
