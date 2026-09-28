#!/bin/sh
# The runtime archive references no symbol of the C++ runtime, not even
# weakly, and has no static constructors or destructors. The
# build runs it after the link check (runtime/CMakeLists.txt), and so does
# tests/toolchain/runtime-link.
#
# Usage: check-archive.sh LLVM-NM LLVM-READELF ARCHIVE [STAMP]
# Prints one line and exits 0 when the archive passes, and touches STAMP;
# otherwise prints what it found and exits 1.
set -eu
LC_ALL=C
export LC_ALL

nm=$1
readelf=$2
archive=$3
stamp=${4-}

work=$(mktemp -d "${TMPDIR:-/tmp}/idris-rt-check.XXXXXX")
trap 'rm -rf "$work"' EXIT
trap 'exit 1' HUP INT TERM

if ! "$nm" --print-file-name "$archive" > "$work/nm" 2> "$work/nm.err"; then
  echo "runtime check: $nm failed on $archive"
  cat "$work/nm.err"
  exit 1
fi
# The last two fields of each line are the symbol's type and name; U, w and v
# are the undefined ones.
awk '$(NF-1) ~ /^[Uwv]$/ { print $NF }' "$work/nm" | sort -u > "$work/undefined"
awk '$(NF-1) !~ /^[Uwv]$/ { print $NF }' "$work/nm" | sort -u > "$work/defined"
comm -23 "$work/undefined" "$work/defined" > "$work/external"

# libc, GMP and compiler-rt define only C names, so every mangled name comes
# from the C++ library. The rest is the C++ ABI (but the two __cxa_ functions
# musl defines), the personality routines and the unwinder.
grep -E '^(_Z|__cxa_|__cxxabi|__gxx_|__gcc_personality|_Unwind_|__dynamic_cast$)' "$work/external" |
  grep -vxE '__cxa_atexit|__cxa_finalize' > "$work/cxx" || true

if ! "$readelf" --section-headers "$archive" > "$work/sections" 2> "$work/readelf.err"; then
  echo "runtime check: $readelf failed on $archive"
  cat "$work/readelf.err"
  exit 1
fi
grep -E '[[:space:]]\.(init_array|fini_array|ctors|dtors|preinit_array)([.[:space:]]|$)' "$work/sections" > "$work/constructors" || true

status=0
if [ -s "$work/cxx" ]; then
  echo "runtime check: the runtime references the C++ runtime (TC-RT-2):"
  sed 's/^/  /' "$work/cxx"
  status=1
fi
if [ -s "$work/constructors" ]; then
  echo "runtime check: the runtime has static constructors or destructors (TC-RT-1):"
  sed 's/^/  /' "$work/constructors"
  status=1
fi
[ "$status" -eq 0 ] || exit 1

[ -z "$stamp" ] || : > "$stamp"
echo "runtime check: no C++ runtime symbol referenced, no static constructors"
