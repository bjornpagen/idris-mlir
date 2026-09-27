#!/bin/sh
# Compiles an Idris program: DRV-FLOW-1 or DRV-FLOW-2
# (docs/architecture/12-driver.md). This is the only copy of the chain;
# `make compile` and the tests run it.
#
#     tools/compile.sh [--int | --io] [-p PACKAGE]... [--directive D]... SOURCE OUTPUT
#
# A program whose `main` has type IO goes through DRV-FLOW-2: one idris-mlir
# command, which leaves the program in build/exec/<name of OUTPUT> next to
# SOURCE, with the packages and directives given. Any other goes through
# DRV-FLOW-1: `idris-mlir --check`, idris-mlir-cc and the pinned clang,
# which leave OUTPUT and OUTPUT's object file. --int and --io choose the flow
# instead of the type of `main`.
#
# Each step runs in SOURCE's directory and its output passes through. The
# exit status is that of the step that failed; on success the executable's
# path is printed last. IDRIS_MLIR names the idris-mlir to run (by default
# the one `make build` makes); the Idris environment is the caller's, the
# Makefile's.

root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/tools/toolchain.sh"
idris_mlir=${IDRIS_MLIR:-$root/compiler/build/exec/idris-mlir}

usage() {
  echo "usage: tools/compile.sh [--int | --io] [-p PACKAGE]... [--directive D]... SOURCE OUTPUT" >&2
  exit 2
}

flow=
options=
while [ $# -gt 2 ]; do
  case $1 in
    --int) flow=int ;;
    --io) flow=io ;;
    -p | --directive) options="$options $1 $2"; shift ;;
    *) usage ;;
  esac
  shift
done
[ $# -eq 2 ] || usage
source=$1
output=$2
[ -f "$source" ] || { echo "error: $source: no such file" >&2; exit 1; }
case $output in
  /*) ;;
  *) output=$PWD/$output ;;
esac
directory=$(cd "$(dirname "$source")" && pwd)
file=${source##*/}
stem=${file%.*}

failed() {
  echo "error: compiling $source failed" >&2
  exit "$1"
}

if [ -z "$flow" ]; then
  if grep -Eq '^main[[:space:]]*:[[:space:]]*IO([^[:alnum:]_]|$)' "$source"; then
    flow=io
  else
    flow=int
  fi
fi

cd "$directory" || exit 1

if [ "$flow" = io ]; then
  # DRV-FLOW-2: idris-mlir runs idris-mlir-cc and the pinned clang itself.
  name=${output##*/}
  "$idris_mlir" --no-banner --no-color --no-prelude --cg mlir $options -o "$name" "$file"
  status=$?
  [ "$status" -eq 0 ] || failed "$status"
  echo "$directory/build/exec/$name"
  exit 0
fi

# DRV-FLOW-1, for `main : Int` programs.
log=$(mktemp -d "${TMPDIR:-/tmp}/idris-mlir-compile.XXXXXX") || exit 1
trap 'rm -rf "$log"' EXIT
"$idris_mlir" --no-banner --no-color --no-prelude --cg mlir --inc mlir --check "$file" \
  > "$log/out" 2> "$log/err"
status=$?
cat "$log/out"
cat "$log/err" >&2
[ "$status" -eq 0 ] || failed "$status"

set -- build/ttc/*/"$stem.mlir"
if [ ! -f "$1" ] && grep -q "No incremental compile data" "$log/out" "$log/err"; then
  # PROF-PROG-1: Idris skips the incremental backend for a module that
  # imports one without `mlir` incremental data (the prelude package), and
  # exits 0 without writing anything. The chain reports it.
  line=$(grep -n '^import[[:space:]]' "$file" | head -n 1 | cut -d: -f1)
  line=${line:-1}
  echo "Error: $stem:$line:1--$line:1:mlir backend: $stem: unsupported (PROF-PROG-1): a main : Int program imports nothing" >&2
  failed 1
fi
if [ $# -ne 1 ] || [ ! -f "$1" ]; then
  echo "error: expected one $stem.mlir under build/ttc, found:" "$@" >&2
  failed 1
fi
mlir=$directory/$1

case ${output##*/} in
  ?*.*) object=${output%.*}.o ;;
  *) object=$output.o ;;
esac
mkdir -p "$(dirname "$output")" || exit 1
"$idris_mlir_cc" "$mlir" -o "$object"
status=$?
[ "$status" -eq 0 ] || failed "$status"
# TC-LINK-2: the link of DRV-FLOW-2 (Frontend/Main.idr): a static-PIE
# executable on musl, by lld, with GMP; musl's libc.a holds libm.
"$pinned_cc" --target=x86_64-unknown-linux-musl -fuse-ld=lld -static-pie \
  -Wl,--gc-sections -Wl,--icf=all "$object" -o "$output" -lgmp
status=$?
[ "$status" -eq 0 ] || failed "$status"
echo "$output"
