#!/bin/sh
# The frontend compiled by itself: the stages of self-hosting, after
# `make build` and the fork installed into the frontend's prefix (`make
# self` makes both first).
#
#     tools/self.sh [STAGE]
#
# Stage N is build/self/stageN/: a copy of idris-mlir, and beside it, where
# idris-mlir runs its frontend (by its real path, so a copy, not a link),
# the idris-mlir-front that stage N-1 compiled from compiler/src, with the
# module and Core that compile wrote. Stage 0 is what `make build` made:
# idris-mlir and the frontend Idris built, on Chez. Every stage compiles the
# same copy of compiler/src (build/self/src), against the same prefix, so
# that nothing differs between two stages but the compiler. STAGE (default
# 3) is the last stage made; at 3, stages 2 and 3 must be the same, byte for
# byte: the executable, its module and its Core. Each compile's output is
# kept in build/self/stageN/stdout and stderr, which ends with its phases'
# times (-mlir-timing) and its peak memory (time -l).
root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/tools/toolchain.sh"

last=${1:-3}
self=$root/build/self
mkdir -p "$self"

# The sources, copied once per run: the stages read the same files.
rm -rf "$self/src"
cp -R "$root/compiler/src" "$self/src"
rm -rf "$self/src/build"

# stage N: compile the frontend with stage N-1's pair into stage N.
stage() {
  n=$1
  if [ "$n" -eq 1 ]; then compiler=$idris_mlir; else compiler=$self/stage$((n - 1))/idris-mlir; fi
  out=$self/stage$n
  rm -rf "$out"
  mkdir -p "$out"
  echo "==> stage $n, compiled by ${compiler#"$root"/}"
  started=$(date +%s)
  (cd "$self/src" && /usr/bin/time -l "$compiler" --prefix "$checkout_prefix" \
     -p idris-compiler -p mlir-linear -mlir-timing \
     IdrisMLIR/Frontend/Driver.idr -o "$out/idris-mlir-front") \
    > "$out/stdout" 2> "$out/stderr"
  status=$?
  echo "    exit $status in $(( $(date +%s) - started )) s"
  if [ "$status" -ne 0 ]; then
    tail -30 "$out/stderr" >&2
    exit 1
  fi
  cp -p "$idris_mlir" "$out/idris-mlir"
}

n=1
while [ "$n" -le "$last" ]; do
  stage "$n"
  n=$((n + 1))
done

if [ "$last" -ge 3 ]; then
  for artifact in idris-mlir-front idris-mlir-front.mlir idris-mlir-front.core; do
    cmp "$self/stage2/$artifact" "$self/stage3/$artifact" ||
      { echo "error: stage 2 and stage 3 differ in $artifact" >&2; exit 1; }
  done
  echo "stage 2 = stage 3: self-hosting holds"
fi
