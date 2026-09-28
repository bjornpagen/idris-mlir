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
# TC-PIN-3: what the host provides, only to build the pinned tools.
for tool in git make cc c++ python3 m4 curl tar sha256sum timeout scheme chez chezscheme; do
  echo "$tool: $(command -v "$tool" 2> /dev/null || echo 'not found')"
done
if [ -f /usr/include/linux/futex.h ] && [ -d /usr/include/asm-generic ]; then
  echo "Linux UAPI headers: found"
else
  echo "Linux UAPI headers: not found"
fi
if [ -f "$idris_prefix/provenance.json" ]; then
  echo "Local Idris/API: built at $(stamp_field "$idris_prefix" idris2_revision)"
else
  echo "Local Idris/API: not built"
fi
for name in cmake ninja llvm sysroot; do
  if "$pins" "$name" 2> /dev/null; then
    case $name in
      llvm) echo "Pinned llvm: $llvm_version (clang, lld, MLIR; .toolchain/llvm-musl)" ;;
      sysroot) echo "Pinned sysroot: musl $(lock_field musl version), GMP $(lock_field gmp version), the LLVM runtimes" ;;
      *) echo "Pinned $name: $(lock_field "$name" version)" ;;
    esac
  else
    echo "Pinned $name: $(problem "$name")"
  fi
done
for path in compiler/build/exec/idris-mlir build/dev/foreign/idr/idris-mlir-cc \
            build/dev/foreign/idr/idris-mlir-opt; do
  if [ -f "$root/$path" ]; then echo "$path: built"; else echo "$path: not built (make build)"; fi
done
if [ -f "${llvm_bin%/bin}/provenance.json" ]; then
  echo "Local LLVM tools: built at $(stamp_field "${llvm_bin%/bin}" llvm_revision)"
  for tool in clang ld.lld clang-tidy mlir-opt mlir-translate mlir-tblgen opt llc llvm-nm FileCheck \
              not count; do
    case $tool in
      not | count)
        # Test utilities without --version.
        if [ -f "$llvm_bin/$tool" ]; then echo "  $tool: present"; else echo "  $tool: MISSING"; fi
        ;;
      ld.lld)
        if "$llvm_bin/$tool" --version 2> /dev/null | grep -qF "LLD $llvm_version"; then
          echo "  $tool: matches lock"
        else
          echo "  $tool: VERSION MISMATCH"
        fi
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
  echo "Local LLVM tools: not built"
fi
