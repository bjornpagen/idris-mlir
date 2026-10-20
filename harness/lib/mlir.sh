# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# The modules a compilation dumps: the ones its checks read.

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
# (--mlir-print-debuginfo), which the checks' errors name.
#
# A dump costs its printing and its parsing again, and the program's every
# step holds the whole prelude it reaches, megabytes a print: a compilation
# dumps the steps its checks read and no other. A step a check reads is
# `after:PASS`, the module after the top-level pass PASS, or
# `before:PASS`, the module PASS is given; `all` is the module after every
# top-level pass, which the determinism checks compare.

# checked_steps FIXTURE: the steps the checks of the e2e FIXTURE read, one
# per line, the one place that says it: what heap-free reads, the module
# idr-lower lowers; and the step of each line of its mlir.expect but the
# emitted module, which no dump holds.
checked_steps() {
  [ -f "$1/heap-free" ] && say before:idr-lower
  [ -f "$1/mlir.expect" ] &&
    sed -n 's/^\([a-z][a-z0-9-]*\):.*/\1/p' "$1/mlir.expect" | grep -vx emitted | sort -u | sed 's/^/after:/'
  return 0
}

# dump_options DIR STEP...: the options of a compilation that prints the
# modules of the steps STEP... under DIR, one per line; none when no step
# is read. MLIR names the dump before a pass and the one after it alike,
# so no pass is read both ways (a usage error, status 1).
dump_options() {
  dump_dir=$1
  shift
  dump_after=
  dump_before=
  dump_all=
  for dump_step in "$@"; do
    case $dump_step in
      all) dump_all=yes ;;
      after:*) dump_after="$dump_after,${dump_step#after:}" ;;
      before:*) dump_before="$dump_before,${dump_step#before:}" ;;
      *) echo "dump_options: $dump_step is no step (after:PASS, before:PASS or all)" >&2; return 1 ;;
    esac
  done
  for dump_pass in $(say "${dump_before#,}" | tr ',' ' '); do
    case ",${dump_after#,}," in
      *",$dump_pass,"*) echo "dump_options: $dump_pass is read before and after, which MLIR's dumps name alike" >&2; return 1 ;;
    esac
  done
  [ -n "$dump_all$dump_after$dump_before" ] || return 0
  if [ -n "$dump_all" ]; then say --mlir-print-ir-after-all; fi
  if [ -z "$dump_all" ] && [ -n "$dump_after" ]; then say "--mlir-print-ir-after=${dump_after#,}"; fi
  if [ -n "$dump_before" ]; then say "--mlir-print-ir-before=${dump_before#,}"; fi
  say "--mlir-print-ir-tree-dir=$dump_dir"
  say --mlir-print-debuginfo
  # A step's print is nested in the module, so it writes its aliases first
  # (upstream/60): each data type once, not its body at every use.
  say --mlir-print-local-aliases
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
# the first dump of that step under DUMPS, after the pass or before it as
# the compilation dumped it (dump_options reads no pass both ways);
# nothing, and status 1, when that
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
