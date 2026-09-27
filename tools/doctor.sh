#!/bin/sh
# make doctor: what the build needs and what is built (TC-BOOT-1). It
# reports problems and never fails. IDRIS_MLIR_TOOLCHAIN and
# IDRIS_MLIR_IDRIS_SOURCE are as in tools/verify-pins.sh.

root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/tools/toolchain.sh"
pins=$root/tools/verify-pins.sh

lock_field() {
  "$pins" lock "$1" "$2" 2> /dev/null
}

# problem CHECK: the error of a verify-pins check, without `error: `.
problem() {
  "$pins" "$1" 2>&1 > /dev/null | sed 's/^error: //'
}

if revision=$("$pins" revision 2> /dev/null); then
  echo "Idris source: $revision"
else
  echo "Idris source: problem: $(problem source)"
fi
llvm_version=$(lock_field llvm version)
echo "LLVM pin: $(lock_field llvm tag) $(lock_field llvm revision)"
for tool in git make cc bash sha256sum scheme chez chezscheme cmake ninja; do
  echo "$tool: $(command -v "$tool" 2> /dev/null || echo 'not found')"
done
if command -v cc > /dev/null 2>&1 &&
   printf '#include <gmp.h>\n' | cc -E -x c - ${CPPFLAGS-} > /dev/null 2>&1; then
  echo "GMP headers: found"
else
  echo "GMP headers: not found"
fi
if [ -f "$idris_prefix/provenance.json" ]; then
  echo "Local Idris/API: built at $(stamp_field "$idris_prefix" idris2_revision)"
else
  echo "Local Idris/API: not built"
fi
for name in gcc cmake ninja; do
  if "$pins" "$name" 2> /dev/null; then
    echo "Pinned $name: $(lock_field "$name" version)"
  else
    echo "Pinned $name: $(problem "$name")"
  fi
done
for path in compiler/build/exec/idris-mlir build/dev/foreign/idr/idris-mlir-cc \
            build/dev/foreign/idr/idris-mlir-opt; do
  if [ -f "$root/$path" ]; then echo "$path: built"; else echo "$path: not built (make build)"; fi
done
if [ -f "${llvm_bin%/bin}/provenance.json" ]; then
  echo "Local MLIR tools: built at $(stamp_field "${llvm_bin%/bin}" llvm_revision)"
  for tool in mlir-opt mlir-translate mlir-tblgen opt llc llvm-nm FileCheck not count; do
    case $tool in
      not | count)
        # Test utilities without --version.
        if [ -f "$llvm_bin/$tool" ]; then echo "  $tool: present"; else echo "  $tool: MISSING"; fi
        ;;
      *)
        if "$llvm_bin/$tool" --version 2> /dev/null | grep -qF "version $llvm_version"; then
          echo "  $tool: matches lock"
        else
          echo "  $tool: VERSION MISMATCH"
        fi
        ;;
    esac
  done
else
  echo "Local MLIR tools: not built"
fi
