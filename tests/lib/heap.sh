# What an e2e program needs outside itself, and whether it allocates.
#
# Its object's undefined symbols are what the runtime it is linked with
# imports (read from the runtime's archive, so the list follows the
# runtime), the calls code generation makes by itself, and what a
# `symbols` file next to the tests adds for them (tests/e2e/v2/symbols:
# libm, for Doubles). Anything else is a call the program should not make.
#
# A file `heap-free` in a test's directory, or in the directory of its
# tests for all of them (tests/e2e/v0/heap-free), marks a program whose
# values the compiler keeps off the heap: no op of the module that is
# lowered allocates a heap cell (idr-expect's no-heap-allocation). The mark
# is the test: the day an optimization stops keeping those values off the
# heap, it fails.

runtime_archive=$root/build/dev/runtime/libidris_rt.a

# The calls LLVM makes by itself, for copies and fills.
codegen_symbols='memcpy memset memmove'

# runtime_imports: the symbols the runtime archive imports: undefined in
# it and defined by none of its members.
runtime_imports() {
  "$llvm_bin/llvm-nm" --print-file-name "$runtime_archive" > "$work/runtime.nm" 2> /dev/null || return 0
  awk '$(NF-1) ~ /^[Uwv]$/ { print $NF }' "$work/runtime.nm" | sort -u > "$work/runtime.undefined"
  awk '$(NF-1) !~ /^[Uwv]$/ { print $NF }' "$work/runtime.nm" | sort -u > "$work/runtime.defined"
  comm -23 "$work/runtime.undefined" "$work/runtime.defined"
}

# allowed_symbols TEST: the calls allowed to the program of the test
# directory TEST.
allowed_symbols() {
  allowed_tests=$(cd "$1/.." && pwd)
  say "$codegen_symbols"
  runtime_imports
  [ -f "$allowed_tests/symbols" ] && sed '/^#/d' "$allowed_tests/symbols"
  return 0
}

# object_imports OBJECT TEST: the object's undefined symbols (llvm-nm) are
# among those allowed to the program of the test directory TEST.
object_imports() {
  if ! "$llvm_bin/llvm-nm" --undefined-only --format=just-symbols "$1" > "$work/nm.out" 2> "$work/nm.err"; then
    say "object: llvm-nm failed"
    show "$work/nm.err"
    return
  fi
  object_allowed=" $(allowed_symbols "$2" | tr '\n' ' ') "
  object_extra=
  for object_symbol in $(sort -u "$work/nm.out"); do
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

# heap_marked TEST: the test directory TEST, or its tests' directory, has
# the mark `heap-free`.
heap_marked() {
  [ -f "$1/heap-free" ] || [ -f "$1/../heap-free" ]
}

# heap_free TEST DUMPS: for a marked test, nothing in the module that
# idr-lower lowers, the last dumped before it in DUMPS, allocates a heap
# cell; for any other, nothing.
heap_free() {
  heap_marked "$1" || return 0
  heap_module=
  for heap_dump in "$2"/[0-9]*-*.mlir; do
    case $heap_dump in *-idr-lower.mlir) break ;; esac
    [ -f "$heap_dump" ] && heap_module=$heap_dump
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
