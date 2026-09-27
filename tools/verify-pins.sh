#!/bin/sh
# The pins (TC-PIN-1, TC-PIN-2): the Idris submodule at its staged gitlink,
# and the provenance stamps of the tools built under .toolchain/, which
# commands refuse when missing or stale.
#
#     tools/verify-pins.sh             the Idris source matches its pin (make verify-pins)
#     tools/verify-pins.sh CHECK...    each CHECK, silent when it passes:
#
#   source      the Idris checkout is the staged gitlink, without modifications
#   revision    the same, printing the revision
#   idris       the local Idris 2 was built from that checkout
#   llvm        the local LLVM/MLIR was built at the lock's revision
#   gcc, cmake, ninja
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
      ;;
    llvm)
      prefix=${llvm_bin%/bin}
      [ -f "$prefix/provenance.json" ] ||
        fail "Build the pinned MLIR tools with tools/bootstrap.sh llvm first"
      [ "$(stamp_field "$prefix" llvm_revision)" = "$(lock_field llvm revision)" ] ||
        fail "Local LLVM tools are stale; rerun tools/bootstrap.sh llvm"
      ;;
    gcc | cmake | ninja)
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
