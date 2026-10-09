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
#   sysroot     the target's C library, the LLVM runtimes and GMP are the
#               ones the toolchain was built with: the lock's revisions, and
#               the SDK the host has now where libSystem is the C library
#   cmake, ninja, chez
#               the pinned tool's stamp names the lock's revision
#
# Idris, LLVM (its runtimes too) and Chez Scheme are also stale when their
# stamp records other patches than upstream/*/<project>.patch carry now
# (tools/patches.sh).
#   built       the tools `make build` makes exist
#   prefix      the frontend's prefix is built: the pinned Idris source's
#               packages and those of libs/, each by the frontend (make build)
#   test-tools  the pinned LLVM has FileCheck, not and count
#
#     tools/verify-pins.sh lock TOOL KEY    prints a string of the lock
#
# A check that fails prints `error: <why and what to run>` and exits 1.
# IDRIS_MLIR_TOOLCHAIN and IDRIS_MLIR_IDRIS_SOURCE stand for .toolchain and
# third_party/Idris2 (the tests under tests/spec use them).

root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/tools/toolchain.sh"
. "$root/tools/patches.sh"
idris_source=${IDRIS_MLIR_IDRIS_SOURCE:-$root/third_party/Idris2}
lock=$root/toolchain.lock.json

fail() {
  echo "error: $*" >&2
  exit 1
}

# patched PROJECT STAMP STEP: the stamp records the patches PROJECT carries
# now (tools/patches.sh); a tool built without one of them, or with one
# that has changed since, is stale.
patched() {
  patched_got=$(sed -n 's/.*"patches"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$2" 2> /dev/null | head -n 1)
  patched_want=$(patch_stamp "$1") || fail "cannot read upstream/*/$1.patch"
  [ "$patched_got" = "$patched_want" ] ||
    fail "Local $3 was not built with the patches upstream/*/$1.patch carry now; rerun tools/bootstrap.sh $3"
}

# stamp_value FILE KEY: a string of a provenance stamp.
stamp_value() {
  sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" "$1" 2> /dev/null | head -n 1
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
      patched idris "$prefix/provenance.json" idris
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
      patched llvm "$prefix/provenance.json" llvm
      ;;
    sysroot)
      # What programs link against, as the steps that made it recorded it
      # (tools/bootstrap.sh): the target's C library, the runtimes beside the
      # pinned clang, and GMP in the sysroot. The C library's stamp says
      # which it is: musl, at the lock's revision, or libSystem in an SDK,
      # which must be the one the host has now.
      stamp=$sysroot/provenance/libc.json
      [ -f "$stamp" ] || fail "The sysroot has no C library; run: tools/bootstrap.sh libc"
      case $(stamp_value "$stamp" libc) in
        musl)
          [ "$(stamp_value "$stamp" revision)" = "$(lock_field musl revision)" ] ||
            fail "The sysroot's musl is stale; rerun tools/bootstrap.sh libc"
          ;;
        sdk)
          [ "$(stamp_value "$stamp" sdk_version)" = "$(xcrun --show-sdk-version 2> /dev/null)" ] ||
            fail "The toolchain was built against another macOS SDK than the host's; rerun tools/bootstrap.sh libc"
          ;;
        *) fail "The sysroot's C library stamp names no C library; rerun tools/bootstrap.sh libc" ;;
      esac
      stamp=$toolchain/runtimes/provenance.json
      [ -f "$stamp" ] || fail "The LLVM runtimes are missing; run: tools/bootstrap.sh runtimes"
      [ "$(stamp_value "$stamp" revision)" = "$(lock_field llvm revision)" ] ||
        fail "The LLVM runtimes are stale; rerun tools/bootstrap.sh runtimes"
      patched llvm "$stamp" runtimes
      stamp=$sysroot/provenance/gmp.json
      [ -f "$stamp" ] || fail "The sysroot has no gmp; run: tools/bootstrap.sh gmp"
      [ "$(stamp_value "$stamp" revision)" = "$(lock_field gmp revision)" ] ||
        fail "The sysroot's gmp is stale; rerun tools/bootstrap.sh gmp"
      ;;
    cmake | ninja | chez)
      want=$(lock_field "$1" revision)
      { [ -n "$want" ] && [ "$(stamp_field "$toolchain/$1" revision)" = "$want" ]; } ||
        fail "Pinned $1 missing or stale; run: tools/bootstrap.sh $1"
      if [ "$1" = chez ]; then patched chez "$toolchain/chez/provenance.json" chez; fi
      ;;
    built)
      for path in "${dev_prefix#"$root"/}/foreign/idr/idris-mlir" \
                  "${dev_prefix#"$root"/}/foreign/idr/idris-mlir-front" \
                  "${dev_prefix#"$root"/}/foreign/idr/idris-mlir-opt"; do
        [ -f "$root/$path" ] || fail "$path is missing; run: make build"
      done
      ;;
    prefix)
      for stamp in "$prefix_stamp" "$libs_stamp"; do
        [ -f "$checkout_prefix/$stamp" ] ||
          fail "the frontend's prefix is not built; run: make build"
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
