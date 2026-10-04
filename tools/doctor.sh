#!/bin/sh
# make doctor: what the build needs and what is built. It
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
# What the host provides, only to build the pinned tools, and what the
# scripts run on it (tools/host.sh): coreutils' timeout, SHA-256 and, where
# date has no nanoseconds (macOS), perl's clock.
for tool in git make cc c++ python3 m4 curl tar unzip; do
  echo "$tool: $(command -v "$tool" 2> /dev/null || echo 'not found')"
done
echo "timeout: ${timeout_cmd:-not found: $timeout_missing}"
echo "SHA-256: $(command -v sha256sum 2> /dev/null || command -v shasum 2> /dev/null || echo 'not found: sha256sum (coreutils) or shasum')"
case $host_clock in
  date) echo "clock: date's %N" ;;
  perl) echo "clock: perl's Time::HiRes: $(now_ns > /dev/null 2>&1 && echo found || echo 'not found')" ;;
esac
case $(uname -s) in
  Linux)
    if [ -f /usr/include/linux/futex.h ] && [ -d /usr/include/asm-generic ]; then
      echo "Linux UAPI headers: found"
    else
      echo "Linux UAPI headers: not found"
    fi
    ;;
  Darwin)
    if sdk=$(xcrun --show-sdk-path 2> /dev/null) && [ -d "$sdk" ]; then
      echo "macOS SDK: $sdk"
    else
      echo "macOS SDK: not found (xcode-select --install)"
    fi
    # MacPorts' coreutils supply gtimeout and gsha256sum, which the
    # benchmarks and the tests need (coreutils' timeout), and which a
    # non-interactive shell's PATH may not name. Homebrew's names are
    # checked too, since it installs the same two.
    for gnu in gtimeout gsha256sum; do
      echo "coreutils $gnu: $(command -v "$gnu" 2> /dev/null || { [ -x "/opt/local/bin/$gnu" ] && echo "/opt/local/bin/$gnu"; } || echo "not found (sudo port install coreutils)")"
    done
    echo "stack hard limit: $(stack_hard_max 2> /dev/null || echo unknown) KiB (macOS caps it near 64 MiB)"
    ;;
esac
if [ -f "$idris_prefix/provenance.json" ]; then
  echo "Local Idris/API: built at $(stamp_field "$idris_prefix" idris2_revision) on Chez Scheme $(stamp_field "$idris_prefix" scheme_version)"
  "$pins" idris 2> /dev/null || echo "Local Idris/API: problem: $(problem idris)"
else
  echo "Local Idris/API: not built"
fi
for name in cmake ninja chez llvm sysroot; do
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
for path in compiler/build/exec/idris-mlir \
            "${dev_prefix#"$root"/}/foreign/idr/idris-mlir-cc" \
            "${dev_prefix#"$root"/}/foreign/idr/idris-mlir-opt"; do
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
