# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# What an e2e program needs outside itself, and whether it allocates.
#
# Its object's undefined symbols are the runtime's (read from the runtime
# object it is linked with, so the list follows the runtime): the bodies
# the program did not inline, which resolve there, and what the runtime
# itself imports, which the bodies it did inline call; the calls code
# generation makes by itself; and libm's, the one list below
# (libm_symbols). Anything else is a call the program should not make.
#
# A file `heap-free` in a test's directory marks a program whose
# values the compiler keeps off the heap: no op of the module that is
# lowered allocates a heap cell (idr-expect's no-heap-allocation). The mark
# is the test: the day an optimization stops keeping those values off the
# heap, it fails.

# runtime_fact NAME: a fact of the target entry that the build writes
# beside the runtime (runtime/CMakeLists.txt) and the harness reads,
# $dev_prefix/runtime/NAME, in $runtime_fact_value: codegen-symbols, the
# calls LLVM makes by itself for the target (copies, fills, and what else
# its code generation emits), one per line; symbol-prefix, the prefix the
# object format puts before a C name, one line ("_" on Mach-O, empty on
# ELF, which is a fact like any other). Without the file, one line naming
# it and status 1: the harness has no fact to check against, and no check
# runs on a guessed one.
runtime_fact() {
  if [ ! -f "$dev_prefix/runtime/$1" ]; then
    say "object: no $dev_prefix/runtime/$1, which the build writes"
    return 1
  fi
  runtime_fact_value=$(cat "$dev_prefix/runtime/$1")
}

# c_names PREFIX: each line of stdin with PREFIX, the object format's
# symbol prefix, taken off. A tool that prints a symbol prints it with the
# prefix, and no allowed list spells one, so every comparison here is in C
# names.
c_names() {
  sed "s/^$1//"
}

# runtime_symbols PREFIX: what the runtime object every program links
# defines and imports (its native half: the bitcode in it names the same
# symbols), in C names.
runtime_symbols() {
  "$llvm_bin/llvm-nm" --no-llvm-bc --format=just-symbols "$("$idris_mlir" --print-runtime)" 2> /dev/null |
    sort -u | c_names "$1"
}

# The calls code generation makes for Doubles: libm's functions, and those
# LLVM substitutes for `pow` (exp2, ldexp). Any program may hold a Double,
# so every program is allowed them. The runtime's own imports (write,
# read, _exit and getenv, which runtime/Platform/Posix/Files.cpp and
# Process.cpp call) need no list: runtime_symbols reads them off the
# runtime object.
libm_symbols='exp log pow sin cos tan asin acos atan sqrt floor ceil exp2 ldexp'

# allowed_symbols CODEGEN PREFIX: the calls allowed to a program: the code
# generation's calls CODEGEN, the runtime's, and libm's.
allowed_symbols() {
  say "$1"
  runtime_symbols "$2"
  # shellcheck disable=SC2086 # the list is words
  printf '%s\n' $libm_symbols
}

# object_imports OBJECT...: the undefined symbols (llvm-nm) of the objects
# a build wrote, one per bin, or the members of the archive -c wrote, are
# among those allowed to a program. A symbol one object defines and
# another uses is the program's own, so what the objects import is what
# any of them leaves undefined, less what any of them defines.
# Its status is 0 when they are, 1 when anything else is printed.
object_imports() {
  if [ $# -eq 0 ]; then
    say "object: none written"
    return 1
  fi
  runtime_fact codegen-symbols || return 1
  object_codegen=$runtime_fact_value
  runtime_fact symbol-prefix || return 1
  object_prefix=$runtime_fact_value
  if ! "$llvm_bin/llvm-nm" --undefined-only --format=just-symbols "$@" > "$work/nm.raw" 2> "$work/nm.err" ||
     ! "$llvm_bin/llvm-nm" --defined-only --extern-only --format=just-symbols "$@" > "$work/nm.defined" 2>> "$work/nm.err"; then
    say "object: llvm-nm failed"
    show "$work/nm.err"
    return 1
  fi
  # With several files llvm-nm heads each one's symbols with its name, a
  # line ending in a colon, and parts them with blank lines.
  grep -v -e '^$' -e ':$' "$work/nm.defined" | c_names "$object_prefix" | LC_ALL=C sort -u > "$work/nm.own"
  grep -v -e '^$' -e ':$' "$work/nm.raw" | c_names "$object_prefix" | LC_ALL=C sort -u |
    LC_ALL=C comm -23 - "$work/nm.own" > "$work/nm.out"
  object_allowed=" $(allowed_symbols "$object_codegen" "$object_prefix" | tr '\n' ' ') "
  object_extra=
  for object_symbol in $(cat "$work/nm.out"); do
    case $object_allowed in
      *" $object_symbol "*) ;;
      *) object_extra="$object_extra $object_symbol" ;;
    esac
  done
  if [ -z "$object_extra" ]; then
    say "object: no undefined symbol outside the allowed set"
  else
    say "object: undefined symbols outside the allowed set:$object_extra"
    return 1
  fi
}

# heap_free TEST DUMPS: for a marked test, nothing in the module that
# idr-lower lowers, the last step dumped before it in DUMPS, allocates a
# heap cell; for any other, nothing. Without a dump of idr-lower the
# module it lowers is not known, and the check fails rather than read the
# last dump, a lowered module, of which the property holds vacuously.
heap_free() {
  [ -f "$1/heap-free" ] || return 0
  heap_module=
  heap_lowered=
  for heap_dump in $(step_dumps "$2"); do
    if [ "$(step_of "$heap_dump")" = idr-lower ]; then
      heap_lowered=yes
      break
    fi
    heap_module=$heap_dump
  done
  if [ -z "$heap_lowered" ]; then
    say "heap: no module dumped after idr-lower, so the module it lowers is not known"
  elif [ -z "$heap_module" ]; then
    say "heap: no module was dumped before lowering"
  elif expect_holds "$heap_module" no-heap-allocation; then
    say "heap: nothing is allocated on the heap"
  else
    say "heap: allocates, though marked heap-free"
    show "$work/expect.log"
  fi
}
