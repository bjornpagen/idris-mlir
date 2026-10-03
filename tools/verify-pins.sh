#!/bin/sh
# The pins: the Idris submodule at its staged gitlink,
# and the provenance stamps of the tools built under .toolchain/, which
# commands refuse when missing or stale.
#
#     tools/verify-pins.sh             the Idris source matches its pin (make verify-pins)
#     tools/verify-pins.sh CHECK...    each CHECK, silent when it passes:
#
#   source      the Idris checkout is the staged gitlink, without modifications
#   revision    the same, printing the revision
#   idris       the local Idris 2 was built from that checkout, on the pinned
#               Chez Scheme
#   llvm        the stage-2 LLVM/MLIR and clang were built at the lock's revision
#   sysroot     musl, the LLVM runtimes and GMP were built into the sysroot at
#               the lock's revisions
#   cmake, ninja, chez
#               the pinned tool's stamp names the lock's revision
#   built       the tools `make build` makes exist
#   test-tools  the pinned LLVM has FileCheck, not and count
#
#     tools/verify-pins.sh lock TOOL KEY    prints a string of the lock
#
# A check that fails prints `error: <why and what to run>` and exits 1.
# IDRIS_MLIR_TOOLCHAIN and IDRIS_MLIR_IDRIS_SOURCE stand for .toolchain and
# third_party/Idris2 (the tests under tests/spec use them).

root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/tools/toolchain.sh"
idris_source=${IDRIS_MLIR_IDRIS_SOURCE:-$root/third_party/Idris2}
lock=$root/toolchain.lock.json

fail() {
  echo "error: $*" >&2
  exit 1
}

# lock_field TOOL KEY: a string of toolchain.lock.json. Schemas 3 and 4 both
# have one object per tool, one field per line.
lock_field() {
  schema=$(sed -n 's/^[[:space:]]*"schema_version"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$lock")
  case $schema in
    3 | 4) ;;
    *) fail "Unsupported toolchain lock schema" ;;
  esac
  awk -v tool="$1" -v key="$2" '
    /^[ \t]*"[^"]*"[ \t]*:[ \t]*\{/ { split($0, parts, "\""); object = parts[2]; next }
    /^[ \t]*\}/ { object = ""; next }
    object == tool {
      line = $0
      if (match(line, "^[ \t]*\"" key "\"[ \t]*:[ \t]*\"")) {
        value = substr(line, RLENGTH + 1)
        sub(/".*$/, "", value)
        print value
        exit
      }
    }' "$lock"
}

# The Idris checkout is the staged gitlink, unmodified; sets $revision.
source_revision() {
  [ -e "$idris_source/.git" ] || fail "Idris source missing; run: git submodule update --init"
  entry=$(git -C "$root" ls-files --stage -- third_party/Idris2) || fail "git ls-files failed"
  set -- $entry
  { [ $# -ge 2 ] && [ "$1" = 160000 ]; } || fail "third_party/Idris2 is not a submodule entry"
  pin=$2
  revision=$(git -C "$idris_source" rev-parse HEAD) || fail "git rev-parse failed in $idris_source"
  [ "$revision" = "$pin" ] || fail "Idris checkout is $revision; the staged pin is $pin"
  modified=$(git -C "$idris_source" status --porcelain --untracked-files=no) || fail "git status failed in $idris_source"
  [ -z "$modified" ] || fail "third_party/Idris2 has tracked modifications"
}

check() {
  case $1 in
    source) source_revision ;;
    revision) source_revision; echo "$revision" ;;
    idris)
      prefix=$idris_prefix
      { [ -f "$prefix/provenance.json" ] && [ -f "$prefix/bin/idris2" ]; } ||
        fail "Build the local Idris 2 with tools/bootstrap.sh idris first"
      source_revision
      [ "$(stamp_field "$prefix" idris2_revision)" = "$revision" ] ||
        fail "Local Idris toolchain is stale; rerun tools/bootstrap.sh idris"
      # Idris runs on the Chez Scheme it was built with: the pinned one.
      check chez
      [ "$(stamp_field "$prefix" chez_revision)" = "$(lock_field chez revision)" ] ||
        fail "Local Idris 2 was built on another Chez Scheme than the pinned one; rerun tools/bootstrap.sh idris"
      ;;
    llvm)
      prefix=${llvm_bin%/bin}
      [ -f "$prefix/provenance.json" ] ||
        fail "Build the pinned MLIR tools with tools/bootstrap.sh llvm first"
      [ "$(stamp_field "$prefix" llvm_revision)" = "$(lock_field llvm revision)" ] ||
        fail "Local LLVM tools are stale; rerun tools/bootstrap.sh llvm"
      ;;
    sysroot)
      # What programs link against, by host. On Linux the sysroot holds
      # musl, the LLVM runtimes and GMP, and the stamps of the steps that
      # filled it (tools/bootstrap.sh), each at the lock's revision of what
      # it built. On Darwin the C library is libSystem in the SDK and the
      # runtimes sit in the pinned clang's resource directory; only GMP is
      # built into the sysroot.
      case $(uname -s) in
        Darwin)
          sdk=$(xcrun --show-sdk-path 2> /dev/null) ||
            fail "no macOS SDK; run: xcode-select --install"
          [ -d "$sdk" ] || fail "the macOS SDK path $sdk is not a directory"
          [ -f "$llvm_prefix/provenance.json" ] ||
            fail "Build the pinned LLVM/MLIR with tools/bootstrap.sh stage2 first"
          # The pinned libc++ and compiler-rt's builtins: on Darwin the
          # builtins are one OS library (libclang_rt.osx.a), not the
          # per-triple libclang_rt.builtins.a Linux installs.
          for runtime in libc++.a 'libclang_rt.*.a'; do
            found=$(find "$llvm_prefix/lib/clang" -name "$runtime" -print -quit 2> /dev/null)
            [ -n "$found" ] || fail "the pinned clang has no $runtime under $llvm_prefix/lib/clang; rerun tools/bootstrap.sh stage2"
          done
          stamp=$sysroot/provenance/gmp.json
          [ -f "$stamp" ] || fail "The sysroot has no gmp; run: tools/bootstrap.sh gmp"
          got=$(sed -n 's/.*"revision"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$stamp" | head -n 1)
          [ "$got" = "$(lock_field gmp revision)" ] ||
            fail "The sysroot's gmp is stale; rerun tools/bootstrap.sh gmp"
          ;;
        *)
          for part in musl:musl runtimes:llvm gmp:gmp; do
            step=${part%%:*}
            stamp=$sysroot/provenance/$step.json
            [ -f "$stamp" ] || fail "The sysroot has no $step; run: tools/bootstrap.sh $step"
            got=$(sed -n 's/.*"revision"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$stamp" | head -n 1)
            [ "$got" = "$(lock_field "${part#*:}" revision)" ] ||
              fail "The sysroot's $step is stale; rerun tools/bootstrap.sh $step"
          done
          ;;
      esac
      ;;
    cmake | ninja | chez)
      want=$(lock_field "$1" revision)
      { [ -n "$want" ] && [ "$(stamp_field "$toolchain/$1" revision)" = "$want" ]; } ||
        fail "Pinned $1 missing or stale; run: tools/bootstrap.sh $1"
      ;;
    built)
      for path in compiler/build/exec/idris-mlir build/dev/foreign/idr/idris-mlir-cc \
                  build/dev/foreign/idr/idris-mlir-opt; do
        [ -f "$root/$path" ] || fail "$path is missing; run: make build"
      done
      ;;
    test-tools)
      for tool in FileCheck not count; do
        [ -f "$llvm_bin/$tool" ] ||
          fail "$tool is missing from the pinned LLVM; run: tools/bootstrap.sh llvm"
      done
      ;;
    *) fail "unknown check: $1 (see tools/verify-pins.sh)" ;;
  esac
}

if [ $# -eq 0 ]; then
  source_revision
  echo "Idris source matches its pin: $revision"
  exit 0
fi
if [ "$1" = lock ] && [ $# -eq 3 ]; then
  # tools/verify-pins.sh lock TOOL KEY: a field of the lock, for doctor.sh.
  value=$(lock_field "$2" "$3") || exit 1
  [ -n "$value" ] || fail "toolchain.lock.json has no $2.$3"
  echo "$value"
  exit 0
fi
for name in "$@"; do
  check "$name"
done
