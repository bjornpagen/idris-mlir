#!/bin/sh
# Compiles an Idris program. This is the only copy of the chain; `make
# compile` and the tests run it.
#
#     tools/compile.sh [-p PACKAGE]... [--directive D]... SOURCE OUTPUT
#
# One idris-mlir command, which runs idris-mlir-cc and the pinned clang
# itself and leaves the program in build/exec/<name of OUTPUT> next to
# SOURCE, with the packages and directives given. It runs in SOURCE's
# directory and its output passes through; the exit status is that of the
# step that failed, and on success the executable's path is printed last.
# The idris-mlir it runs is the one `make build` makes; the Idris
# environment is the caller's, the Makefile's.
#
# Two directives reach idris-mlir-cc as its options of the same name:
# `no-eval` and `demand-in-place`; `dump-mlir` dumps the module after every
# step under build/exec.
root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/tools/toolchain.sh"
idris_mlir=$root/compiler/build/exec/idris-mlir

usage() {
  echo "usage: tools/compile.sh [-p PACKAGE]... [--directive D]... SOURCE OUTPUT" >&2
  exit 2
}
options=
while [ $# -gt 2 ]; do
  case $1 in
    -p) options="$options $1 $2"; shift ;;
    --directive) options="$options $1 $2"; shift ;;
    *) usage ;;
  esac
  shift
done
[ $# -eq 2 ] || usage
source=$1
output=$2
[ -f "$source" ] || { echo "error: $source: no such file" >&2; exit 1; }
directory=$(cd "$(dirname "$source")" && pwd)
file=${source##*/}
name=${output##*/}
cd "$directory" || exit 1
# shellcheck disable=SC2086 # the options are words
"$idris_mlir" --no-banner --no-color --no-prelude --cg mlir $options -o "$name" "$file"
status=$?
[ "$status" -eq 0 ] || { echo "error: compiling $source failed" >&2; exit "$status"; }
echo "$directory/build/exec/$name"
