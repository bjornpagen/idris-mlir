# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# The modules a compilation dumps, one after each top-level pass.

# The modules a compilation passes through are upstream's IR tree printer's
# (dump_options): after each pass, the op it ran on, in a file of its own
# under the dump directory, one directory per op from the module down. A
# pass on the module prints it as `<m>_<pass>.mlir` directly inside the
# one `builtin_module_*` directory, m counting the module's prints from 0;
# a pass on the program prints the program, which reads back as a module
# holding it, as `<m>_<n>_<pass>.mlir` in the program's `idr_program_*`
# directory, n counting the program's prints and m the module's before it,
# so the two numbers order every step; a pass nested in a group over
# functions prints only its function, one directory further down, so a
# group is no step. The printer keeps every location
# (--mlir-print-debuginfo), which the quantities and the checks read.

# dump_options DIR: the options of a compilation that prints its modules
# under DIR, one per line.
dump_options() {
  say --mlir-print-ir-after-all
  say "--mlir-print-ir-tree-dir=$1"
  say --mlir-print-debuginfo
}

# step_dumps DIR: the module, or the program, after each top-level pass, in
# the order the passes ran, one path per line. A module's print sorts
# before the program's prints that follow it (n is -1 for it).
step_dumps() {
  for step_dumps_dir in "$1"/builtin_module_*; do
    [ -d "$step_dumps_dir" ] || continue
    {
      find "$step_dumps_dir" -maxdepth 1 -type f -name '[0-9]*_*.mlir'
      find "$step_dumps_dir" -mindepth 2 -maxdepth 2 -type f -path '*/idr_program_*/*' -name '[0-9]*_*.mlir'
    } 2> /dev/null |
      awk '{ name = $0; sub(/^.*\//, "", name); m = name; sub(/_.*$/, "", m)
             rest = name; sub(/^[0-9]+_/, "", rest); n = -1
             if (rest ~ /^[0-9]+_/) { n = rest; sub(/_.*$/, "", n) }
             print m "\t" n "\t" $0 }' |
      sort -k 1,1n -k 2,2n | cut -f 3-
  done
}

# step_of DUMP: the pass a dump of step_dumps is the module after: its name
# without the counts before it.
step_of() {
  step_of_name=$(say "${1##*/}" | sed 's/^\([0-9][0-9]*_\)*//')
  say "${step_of_name%.mlir}"
}

# step_module STEP EMITTED DUMPS: the module of STEP, `emitted` (EMITTED) or
# the first dump of that step under DUMPS; nothing, and status 1, when that
# step left no dump. A step is found by its name, not its number, so it
# survives steps added before it; of two dumps of one step (symbol-dce
# runs more than once) the first is taken. A step that left no dump never
# falls back to another.
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
