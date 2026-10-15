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

# The modules a compilation passes through are upstream's IR tree printer's
# (dump_options): after each pass, the module or the one function it ran
# on, in a file of its own under the dump directory. A top-level pass of
# idris-mlir's pipeline prints the whole module, as `<n>_<pass>.mlir`
# directly inside the one `builtin_module_*` directory, n counting the
# module's prints from 0; a pass nested in a group over functions prints
# only its function, one directory further down, so a group is no step.
# The printer keeps every location (--mlir-print-debuginfo), which the
# quantities and the checks read.

# dump_options DIR: the options of a compilation that prints its modules
# under DIR, one per line.
dump_options() {
  say --mlir-print-ir-after-all
  say "--mlir-print-ir-tree-dir=$1"
  say --mlir-print-debuginfo
}

# step_dumps DIR: the module after each top-level pass, in the order the
# passes ran, one path per line.
step_dumps() {
  for step_dumps_dir in "$1"/builtin_module_*; do
    [ -d "$step_dumps_dir" ] || continue
    find "$step_dumps_dir" -maxdepth 1 -type f -name '[0-9]*_*.mlir' 2> /dev/null |
      awk '{ n = $0; sub(/^.*\//, "", n); sub(/_.*$/, "", n); print n "\t" $0 }' |
      sort -n -k 1,1 | cut -f 2-
  done
}

# step_of DUMP: the pass a dump of step_dumps is the module after.
step_of() {
  step_of_name=${1##*/}
  step_of_name=${step_of_name#*_}
  say "${step_of_name%.mlir}"
}

# An mlir.check file is FileChecked against one module of the compilation.
# Its first line chooses which:
#
#     // input: emitted              the module the frontend handed the
#                                    driver
#     // input: after <step>         the module after that top-level pass
#                                    of idris-mlir's pipeline
#
# and without either, the module after `idr-optimize`, the optimizer,
# where the eliminations are done and nothing is lowered yet. A step's
# module is the first of step_dumps that names it, found by the step's
# name and not by its number, so it survives steps added before it; of
# two dumps of a step (canonicalize runs more than once) the first is
# taken. A step that left no dump fails the check, never falls back to
# another.
#
# idris-mlir-opt parses the module a check reads and prints it again,
# every location and type written where it is used (no alias) and each op
# in its dialect's syntax. So a check states the module, the same however
# the frontend or a dump spells it, bytecode included; an op under an
# idr.func prints without its `idr.` prefix.

# mlir_input CHECK: `emitted`, or the step whose module CHECK reads.
mlir_input() {
  mlir_input_first=$(head -n 1 "$1")
  case $mlir_input_first in
    *'// input: emitted'*) say emitted ;;
    *'// input: after '*) say "${mlir_input_first##*// input: after }" | awk '{ print $1 }' ;;
    *) say idr-optimize ;;
  esac
}

# step_module STEP EMITTED DUMPS: the module of STEP, `emitted` (EMITTED) or
# the first dump of that step under DUMPS; nothing, and status 1, when that
# step left no dump.
step_module() {
  if [ "$1" = emitted ]; then
    say "$2"
    return
  fi
  step_module_file=
  for step_module_dump in $(step_dumps "$3"); do
    if [ "$(step_of "$step_module_dump")" = "$1" ]; then
      step_module_file=$step_module_dump
      break
    fi
  done
  [ -n "$step_module_file" ] && say "$step_module_file"
}

# check_mlir CHECK EMITTED DUMPS: FileCheck of CHECK on its input, the emitted
# module EMITTED or a module of the directory DUMPS.
check_mlir() {
  check_mlir_step=$(mlir_input "$1")
  if ! check_mlir_file=$(step_module "$check_mlir_step" "$2" "$3"); then
    say "${1##*/}: no module dumped after $check_mlir_step"
    step_dumps "$3" | sed 's|^.*/||; s/^/  | /'
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
