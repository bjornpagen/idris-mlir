#!/bin/sh
# Compiles an Idris program with idris-mlir: the one copy of how `make
# compile`, the tests and the benchmarks run it.
#
#     tools/compile.sh [OPTION]... SOURCE OUTPUT
#
# idris-mlir runs in SOURCE's directory, the root of the program's modules,
# with --no-prelude and OPTION... as given (-p PACKAGE, --no-eval,
# --demand-in-place, --dump-dir=DIR, --break-shape=KEY). It leaves the
# executable in build/exec/<name of OUTPUT> there, with its .core, .mlir
# and .o beside it. Its output passes through, and the exit status is
# idris-mlir's (3 for an error of the program's); on success the
# executable's path is printed last. The idris-mlir it runs is the one
# `make build` makes.
root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/tools/toolchain.sh"

[ $# -ge 2 ] || { echo "usage: tools/compile.sh [OPTION]... SOURCE OUTPUT" >&2; exit 2; }
# The last two arguments are SOURCE and OUTPUT; the options stay in "$@".
n=$#
i=0
for argument do
  i=$((i + 1))
  if [ "$i" -eq $((n - 1)) ]; then
    source=$argument
  elif [ "$i" -eq "$n" ]; then
    output=$argument
  else
    set -- "$@" "$argument"
  fi
done
shift "$n"
[ -f "$source" ] || { echo "error: $source: no such file" >&2; exit 1; }
directory=$(cd "$(dirname "$source")" && pwd)
name=${output##*/}
cd "$directory" && mkdir -p build/exec || exit 1
"$idris_mlir" --no-prelude "$@" "${source##*/}" -o "build/exec/$name"
status=$?
[ "$status" -eq 0 ] || { echo "error: compiling $source failed" >&2; exit "$status"; }
echo "$directory/build/exec/$name"
