# What an object calls outside itself: its undefined symbols.

# heap_free OBJECT SYMBOL...: the object's undefined symbols (llvm-nm) are
# among SYMBOLs: no malloc, no runtime, no other libc call.
heap_free() {
  heap_object=$1
  shift
  if ! "$llvm_bin/llvm-nm" --undefined-only --format=just-symbols "$heap_object" > "$work/nm.out" 2> "$work/nm.err"; then
    say "object: llvm-nm failed"
    show "$work/nm.err"
    return
  fi
  heap_extra=
  for heap_symbol in $(sort -u "$work/nm.out"); do
    case " $* " in
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

v0_symbols='write _exit'
v1_symbols='write read _exit'
# v2 programs may also call these libm functions, including the ones LLVM
# substitutes for pow.
v2_symbols="$v1_symbols exp log pow sin cos tan asin acos atan sqrt floor ceil exp2 ldexp"
