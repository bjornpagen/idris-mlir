#!/bin/sh
# Lowers a hand-written program of bench/gate/lowered with the pinned LLVM
# tools and links it with the runtime prototype (foreign/idr/bench/gate):
#
#   bench/gate/lower.sh NAME [VARIANT]       a program: rbtree, deriv,
#                                            binarytrees, linrb-static,
#                                            linrb-dynamic, ptrees, shmap,
#                                            pipe; prints the executable
#   bench/gate/lower.sh -o EXE VARIANT FILE.mlir...
#                                            any files, after the prelude
#
# VARIANT selects the runtime's build: plain (default), stats, flush, home,
# flush-home (bench/gate/README.md). The steps are lib.sh's lower: the
# prelude and the files are concatenated, then
#   mlir-opt   canonicalize, cse, convert-scf-to-cf, convert-to-llvm,
#              reconcile-unrealized-casts (idris-mlir-cc's steps 9-10)
#   mlir-translate --mlir-to-llvmir
#   opt        internalize all but idr_main, then O3, for x86-64-v3
#   llc        O3, PIC, functions and unreachable blocks on 64-byte lines
# and the object is linked with the runtime by $CXX.
set -eu
GATE=$(cd "$(dirname "$0")" && pwd)
. "$GATE/lib.sh"
case ${1:-} in
  '') echo "usage: bench/gate/lower.sh NAME [VARIANT] | -o EXE VARIANT FILE.mlir..." >&2; exit 2 ;;
  -o) [ $# -ge 4 ] || { echo "usage: bench/gate/lower.sh -o EXE VARIANT FILE.mlir..." >&2; exit 2; }
      exe=$2; variant=$3; shift 3; lower "$exe" "$variant" "$@" ;;
  *) build_lowered "$1" "${2:-plain}" ;;
esac
