# What an e2e program's object calls outside itself, its undefined symbols,
# are the C library calls its fixture allows, which are data:
#   - tests/e2e/<version>/symbols: the calls every program of the version
#     may make (output, exit, input, libm);
#   - a file `heap-free` in the fixture, or in its version for all of its
#     fixtures: the program allocates nothing on the heap, so it makes none
#     of the allocator's calls. Without one, it may.
# A program that must stay off the heap is marked, and the mark is the
# test: the day an optimization stops keeping its values off the heap, the
# allocator's calls appear and the test fails.

# The system calls through which the allocator gets and returns memory.
allocator_symbols='mmap munmap madvise syscall abort __errno_location'

# allowed_symbols TEST: the calls allowed to the program of the e2e test
# directory TEST.
allowed_symbols() {
  allowed_test=$(cd "$1" && pwd)
  allowed_version=${allowed_test%/*}
  sed '/^#/d' "$allowed_version/symbols"
  [ -f "$allowed_test/heap-free" ] || [ -f "$allowed_version/heap-free" ] || say "$allocator_symbols"
}

# heap_free OBJECT TEST: the object's undefined symbols (llvm-nm) are among
# those allowed to the program of the e2e test directory TEST: no call of
# the runtime or of the C library that it does not allow.
heap_free() {
  if ! "$llvm_bin/llvm-nm" --undefined-only --format=just-symbols "$1" > "$work/nm.out" 2> "$work/nm.err"; then
    say "object: llvm-nm failed"
    show "$work/nm.err"
    return
  fi
  heap_allowed=" $(allowed_symbols "$2" | tr '\n' ' ') "
  heap_extra=
  for heap_symbol in $(sort -u "$work/nm.out"); do
    case $heap_allowed in
      *" $heap_symbol "*) ;;
      *) heap_extra="$heap_extra $heap_symbol" ;;
    esac
  done
  if [ -z "$heap_extra" ]; then
    say "object: no undefined symbol outside the allowed set"
  else
    say "object: undefined symbols outside the allowed set:$heap_extra"
  fi
}
