#!/bin/sh
# Compiles an Idris program. This is the only copy of the chain; `make
# compile` and the tests run it.
#
#     tools/compile.sh [--int | --io] [-p PACKAGE]... [--directive D]... SOURCE OUTPUT
#
# A program whose `main` has type IO goes through the -o flow: one idris-mlir
# command, which leaves the program in build/exec/<name of OUTPUT> next to
# SOURCE, with the packages and directives given. Any other goes through
# the check flow: `idris-mlir --check`, idris-mlir-cc and the pinned clang,
# which leave OUTPUT and OUTPUT's object file. --int and --io choose the flow
# instead of the type of `main`.
#
# Each step runs in SOURCE's directory and its output passes through. The
# exit status is that of the step that failed, except that idris-mlir-cc's
# user errors (3, a profile rejection; 4, an evaluation the machine cannot
# finish) exit 1, as every other user error of the chain does; on success the
# executable's path is printed last. IDRIS_MLIR names the idris-mlir to run
# (by default the one `make build` makes); the Idris environment is the
# caller's, the Makefile's.
#
# Two directives also reach the idris-mlir-cc that the check flow runs here
# (the -o flow's is run by idris-mlir itself, which reads them too):
# `no-eval` passes --no-eval, and `dump-mlir` passes --dump-after=all with
# OUTPUT.dump as --dump-dir.

root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/tools/toolchain.sh"
idris_mlir=${IDRIS_MLIR:-$root/compiler/build/exec/idris-mlir}

usage() {
  echo "usage: tools/compile.sh [--int | --io] [-p PACKAGE]... [--directive D]... SOURCE OUTPUT" >&2
  exit 2
}

flow=
options=
cc_options=
dump_mlir=
while [ $# -gt 2 ]; do
  case $1 in
    --int) flow=int ;;
    --io) flow=io ;;
    -p) options="$options $1 $2"; shift ;;
    --directive)
      options="$options $1 $2"
      case $2 in
        no-eval) cc_options="$cc_options --no-eval" ;;
        dump-mlir) dump_mlir=yes ;;
      esac
      shift
      ;;
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
  # The -o flow: idris-mlir runs idris-mlir-cc and the pinned clang itself.
  name=${output##*/}
  "$idris_mlir" --no-banner --no-color --no-prelude --cg mlir $options -o "$name" "$file"
  status=$?
  [ "$status" -eq 0 ] || failed "$status"
  echo "$directory/build/exec/$name"
  exit 0
fi

# The check flow, for `main : Int` programs.
log=$(mktemp -d "${TMPDIR:-/tmp}/idris-mlir-compile.XXXXXX") || exit 1
trap 'rm -rf "$log"' EXIT
# shellcheck disable=SC2086 # the options are words
"$idris_mlir" --no-banner --no-color --no-prelude --cg mlir --inc mlir $options --check "$file" \
  > "$log/out" 2> "$log/err"
status=$?
cat "$log/out"
cat "$log/err" >&2
[ "$status" -eq 0 ] || failed "$status"

set -- build/ttc/*/"$stem.mlir"
if [ ! -f "$1" ] && grep -q "No incremental compile data" "$log/out" "$log/err"; then
  # Idris skips the incremental backend for a module that
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
if [ -n "$dump_mlir" ]; then
  mkdir -p "$output.dump" || exit 1
  cc_options="$cc_options --dump-after=all --dump-dir=$output.dump"
fi
# shellcheck disable=SC2086 # the options are words
"$idris_mlir_cc" "$mlir" -o "$object" $cc_options 2> "$log/cc.err"
status=$?
case $status in
  0) cat "$log/cc.err" >&2 ;;
  3 | 4)
    # A profile rejection (3) or an evaluation the machine cannot finish (4)
    # is a user error. The frontend's --check already reports rejections at the
    # user's code, so this is reached only when the full pipeline decides
    # otherwise; its first location is reported as Idris reports one.
    at=$(grep -m 1 -oE '[A-Za-z0-9_./-]+\.idr"?:[0-9]+:[0-9]+' "$log/cc.err" | tr -d '"')
    line=$(printf '%s\n' "$at" | sed -n 's/.*:\([0-9]*\):\([0-9]*\)$/\1/p')
    col=$(printf '%s\n' "$at" | sed -n 's/.*:\([0-9]*\):\([0-9]*\)$/\2/p')
    what=$(grep -m 1 -o 'unsupported (.*' "$log/cc.err")
    [ -n "$what" ] || what="idris-mlir-cc exited $status: $(head -n 1 "$log/cc.err")"
    echo "Error: $stem:${line:-1}:${col:-1}--${line:-1}:${col:-1}:mlir backend: $what" >&2
    # The rest of what it wrote, without a second copy of the rejection.
    grep -v 'unsupported (' "$log/cc.err" >&2
    # A rejected program leaves no artifact.
    rm -f "$object" "$mlir" "${mlir%.mlir}.core"
    failed 1
    ;;
  *)
    cat "$log/cc.err" >&2
    failed "$status"
    ;;
esac
# The link of the -o flow (Frontend/Main.idr): a static-PIE
# executable on musl, by lld, with GMP; musl's libc.a holds libm.
"$pinned_cc" --target=x86_64-unknown-linux-musl -fuse-ld=lld -static-pie \
  -Wl,--gc-sections -Wl,--icf=all "$object" -o "$output" -lgmp
status=$?
[ "$status" -eq 0 ] || failed "$status"
echo "$output"
