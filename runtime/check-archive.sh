#!/bin/sh
# The runtime archive references no symbol of the C++ runtime, not even
# weakly, and has no static constructors or destructors. The build runs it
# after the link check (runtime/CMakeLists.txt), through the wrapper it
# writes with the target entry's spellings (build/<preset>/runtime/
# check-archive), and so does tests/toolchain/runtime-archive-check.
#
# Usage: check-archive.sh LLVM-NM LLVM-OBJDUMP SYMBOL-PREFIX
#                         CONSTRUCTOR-SECTIONS ARCHIVE [STAMP]
# SYMBOL-PREFIX is what the object format puts before a C name ("" on ELF,
# "_" on Mach-O); CONSTRUCTOR-SECTIONS, the names of the sections that hold
# static constructors and destructors, separated by spaces (a section named
# one of them followed by a dot and a priority counts too). Both are the
# target entry's (CMakeLists.txt). LLVM's tools read every object format
# alike, so only these spellings differ between targets.
# Prints one line and exits 0 when the archive passes, and touches STAMP;
# otherwise prints what it found and exits 1. An archive that does not
# define the runtime's entry, idris_rt_start, as a C name fails too: a check
# that reads no name right proves nothing.
set -eu
LC_ALL=C
export LC_ALL

nm=$1
objdump=$2
prefix=$3
constructors=$4
archive=$5
stamp=${6-}

work=$(mktemp -d "${TMPDIR:-/tmp}/idris-rt-check.XXXXXX")
trap 'rm -rf "$work"' EXIT
trap 'exit 1' HUP INT TERM

# Each member's names twice: its native code's, which every link reads, and
# those of the bitcode it carries, which joins every program. llvm-nm reads
# a member that carries bitcode (an ELF fat LTO object's .llvm.lto, a Mach-O
# object's __LLVM,__bitcode) as that bitcode alone unless told not to, so a
# reference only the native code makes (one codegen adds, or a weak one)
# would otherwise go unseen.
if ! { "$nm" --print-file-name --no-llvm-bc "$archive" && "$nm" --print-file-name "$archive"; } \
    > "$work/nm" 2> "$work/nm.err"; then
  echo "runtime check: $nm failed on $archive"
  cat "$work/nm.err"
  exit 1
fi
# The last two fields of each line are the symbol's type and name; U, w and v
# are the undefined ones. The names are C's once the prefix is taken off.
awk -v prefix="$prefix" '
  NF >= 2 {
    name = $NF
    if (prefix != "" && index(name, prefix) == 1) name = substr(name, length(prefix) + 1)
    print (($(NF-1) ~ /^[Uwv]$/) ? "U" : "D"), name
  }' "$work/nm" > "$work/symbols"
awk '$1 == "U" { print $2 }' "$work/symbols" | sort -u > "$work/undefined"
awk '$1 == "D" { print $2 }' "$work/symbols" | sort -u > "$work/defined"
comm -23 "$work/undefined" "$work/defined" > "$work/external"
# The runtime's entry is among its names, read as C's: otherwise the prefix
# is not the object format's, and no name below would be read right.
if ! grep -qx 'idris_rt_start' "$work/defined"; then
  echo "runtime check: $archive defines no idris_rt_start once '$prefix' is taken off its names, so nothing was checked"
  exit 1
fi

# libc, GMP and compiler-rt define only C names, so every mangled name comes
# from the C++ library. The rest is the C++ ABI (but the two __cxa_ functions
# musl defines), the personality routines and the unwinder.
grep -E '^(_Z|__cxa_|__cxxabi|__gxx_|__gcc_personality|_Unwind_|__dynamic_cast$)' "$work/external" |
  grep -vxE '__cxa_atexit|__cxa_finalize' > "$work/cxx" || true

if ! "$objdump" --section-headers "$archive" > "$work/sections" 2> "$work/objdump.err"; then
  echo "runtime check: $objdump failed on $archive"
  cat "$work/objdump.err"
  exit 1
fi
# Each section is a line `INDEX NAME SIZE ...` under a member's header. On
# Mach-O the name is the section's alone, without its segment
# (__mod_init_func, not __DATA,__mod_init_func); the bitcode a member
# carries is a section of its own (__bitcode, __cmdline; .llvm.lto) that
# names no constructor.
awk -v names="$constructors" '
  BEGIN { n = split(names, list, " ") }
  /:[[:space:]]+file format / { member = $1; sub(/:$/, "", member) }
  $1 ~ /^[0-9]+$/ && NF >= 3 {
    for (i = 1; i <= n; i++)
      if ($2 == list[i] || index($2, list[i] ".") == 1) { print member ": " $2; break }
  }' "$work/sections" > "$work/constructors"

status=0
if [ -s "$work/cxx" ]; then
  echo "runtime check: the runtime references the C++ runtime:"
  sed 's/^/  /' "$work/cxx"
  status=1
fi
if [ -s "$work/constructors" ]; then
  echo "runtime check: the runtime has static constructors or destructors:"
  sed 's/^/  /' "$work/constructors"
  status=1
fi
[ "$status" -eq 0 ] || exit 1

[ -z "$stamp" ] || : > "$stamp"
echo "runtime check: no C++ runtime symbol referenced, no static constructors"
