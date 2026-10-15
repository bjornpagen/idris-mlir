# What an e2e program needs outside itself, and whether it allocates.
#
# Its object's undefined symbols are the runtime's (read from the runtime
# object it is linked with, so the list follows the runtime): the bodies
# the program did not inline, which resolve there, and what the runtime
# itself imports, which the bodies it did inline call; the calls code
# generation makes by itself; and what a `symbols` file next to the tests
# adds for them (tests/programs/prelude/symbols: libm, for Doubles).
# Anything else is a call the program should not make.
#
# A file `heap-free` in a test's directory marks a program whose
# values the compiler keeps off the heap: no op of the module that is
# lowered allocates a heap cell (idr-expect's no-heap-allocation). The mark
# is the test: the day an optimization stops keeping those values off the
# heap, it fails.

# The calls LLVM makes by itself for the target (copies, fills, and what
# else its code generation emits): the build writes them from the target
# entry (runtime/CMakeLists.txt, codegen-symbols). A build that predates
# the file falls back to the copy and fill calls every target has.
codegen_symbols=$(cat "$dev_prefix/runtime/codegen-symbols" 2> /dev/null) ||
  codegen_symbols='memcpy memset memmove'

# The prefix the object format puts before a C name ("" on ELF, "_" on
# Mach-O), a target entry fact the build writes (runtime/symbol-prefix): a
# tool that prints a symbol prints it with the prefix, and no allowed list
# spells one, so every comparison here is in C names.
symbol_prefix=$(cat "$dev_prefix/runtime/symbol-prefix" 2> /dev/null) || symbol_prefix=

# c_names: each line of stdin with the object format's symbol prefix taken
# off.
c_names() {
  if [ -n "$symbol_prefix" ]; then
    sed "s/^$symbol_prefix//"
  else
    cat
  fi
}

# runtime_symbols: what the runtime object every program links defines
# and imports (its native half: the bitcode in it names the same symbols).
runtime_symbols() {
  "$llvm_bin/llvm-nm" --no-llvm-bc --format=just-symbols "$("$idris_mlir" --print-runtime)" 2> /dev/null |
    sort -u | c_names
}

# allowed_symbols TEST: the calls allowed to the program of the test
# directory TEST.
allowed_symbols() {
  allowed_tests=$(cd "$1/.." && pwd)
  say "$codegen_symbols"
  runtime_symbols
  [ -f "$allowed_tests/symbols" ] && sed '/^#/d' "$allowed_tests/symbols"
  return 0
}

# object_imports TEST OBJECT...: the undefined symbols (llvm-nm) of the
# objects a build wrote, one per bin, or the members of the archive -c
# wrote, are among those allowed to the program of the test directory TEST.
# A symbol one object defines and another uses is the program's own, so
# what the objects import is what any of them leaves undefined, less what
# any of them defines.
object_imports() {
  object_test=$1
  shift
  if [ $# -eq 0 ]; then
    say "object: none written"
    return
  fi
  if ! "$llvm_bin/llvm-nm" --undefined-only --format=just-symbols "$@" > "$work/nm.raw" 2> "$work/nm.err" ||
     ! "$llvm_bin/llvm-nm" --defined-only --extern-only --format=just-symbols "$@" > "$work/nm.defined" 2>> "$work/nm.err"; then
    say "object: llvm-nm failed"
    show "$work/nm.err"
    return
  fi
  # With several files llvm-nm heads each one's symbols with its name, a
  # line ending in a colon, and parts them with blank lines.
  grep -v -e '^$' -e ':$' "$work/nm.defined" | c_names | LC_ALL=C sort -u > "$work/nm.own"
  grep -v -e '^$' -e ':$' "$work/nm.raw" | c_names | LC_ALL=C sort -u |
    LC_ALL=C comm -23 - "$work/nm.own" > "$work/nm.out"
  object_allowed=" $(allowed_symbols "$object_test" | tr '\n' ' ') "
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
  fi
}

# heap_marked TEST: the test directory TEST has the mark `heap-free`.
heap_marked() {
  [ -f "$1/heap-free" ]
}

# heap_free TEST DUMPS: for a marked test, nothing in the module that
# idr-lower lowers, the last step dumped before it in DUMPS, allocates a
# heap cell; for any other, nothing.
heap_free() {
  heap_marked "$1" || return 0
  heap_module=
  for heap_dump in $(step_dumps "$2"); do
    [ "$(step_of "$heap_dump")" = idr-lower ] && break
    heap_module=$heap_dump
  done
  if [ -z "$heap_module" ]; then
    say "heap: no module was dumped before lowering"
  elif expect_holds "$heap_module" no-heap-allocation; then
    say "heap: nothing is allocated on the heap"
  else
    say "heap: allocates, though marked heap-free"
    show "$work/expect.log"
  fi
}
