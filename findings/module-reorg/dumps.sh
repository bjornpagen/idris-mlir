#!/bin/sh
# dumps.sh WORKTREE OUTDIR: what the reorganization must leave unchanged,
# with WORKTREE's `make build`: the .mlir dump after every step and the .ll
# of fib, rbtree, spectral-norm-linear and k-nucleotide, and the prepared
# runtime's symbols (exported: global, default visibility, defined; and all).
# Writes OUTDIR and OUTDIR.sha256; compare two runs' .sha256 files, which
# must differ at most in runtime-all-symbols.txt (private names).
#
# Take your own baseline before you change anything, in the same worktree:
# a different base commit may differ.
set -eu
root=$1
out=$2
rm -rf "$out"
mkdir -p "$out"
# A fixed place per worktree, so that two runs compile in the same directory.
work=$root/build/r1-dumps-work
rm -rf "$work"
cd "$root"
. "$root/tools/toolchain.sh"
export IDRIS2_PREFIX="$root/build/idris2"
export PATH="$idris_prefix/bin:$PATH"
export IDRIS_MLIR_ROOT="$root"
export CHEZ="$chez_scheme"
unset IDRIS2_PATH IDRIS2_PACKAGE_PATH IDRIS2_INC_CGS IDRIS2_INC_SRC IDRIS2_DATA IDRIS2_LIBS IDRIS2_CG IDRIS2_BOOT
for name in fib rbtree spectral-norm-linear k-nucleotide; do
  dir=$work/$name
  mkdir -p "$dir"
  cp "bench/$name/Main.idr" "$dir/"
  packages=
  if [ -f "bench/$name/packages" ]; then
    for p in $(cat "bench/$name/packages"); do packages="$packages -p $p"; done
  fi
  # shellcheck disable=SC2086
  timeout 900 tools/compile.sh $packages --directive dump-mlir "$dir/Main.idr" prog > "$dir/compile.log" 2>&1 ||
    { echo "compile $name failed"; cat "$dir/compile.log"; exit 1; }
  mkdir -p "$out/$name"
  cp "$dir"/build/exec/prog.dump/*.mlir "$out/$name/"
  input=$(ls "$dir"/build/exec/*.mlir | head -n 1)
  cp "$input" "$out/$name/input.mlir"
  timeout 900 "$idris_mlir_cc" "$input" --emit llvm -o "$out/$name/prog.ll"
done
"$llvm_bin/llvm-readelf" -s --wide build/dev/foreign/idr/idris_rt.o |
  awk '$5 == "GLOBAL" && $6 == "DEFAULT" && $7 != "UND" {print $4, $8}' | sort > "$out/runtime-symbols.txt"
"$llvm_bin/llvm-readelf" -s --wide build/dev/foreign/idr/idris_rt.o |
  awk '$7 != "UND" && NF >= 8 {print $5, $6, $4, $8}' | sort > "$out/runtime-all-symbols.txt"
rm -rf "$work"
(cd "$out" && find . -type f | sort | xargs sha256sum) > "$out.sha256"
wc -l < "$out.sha256"
