#!/bin/sh
# many-values.sh N: one function of N chained integer additions, on standard
# output. `mlir-opt -sccp` (or -int-range-optimizations) on it gives every
# value a state; the solver's heap per state is the patch's measure, read as
# the peak resident set over N (about 2.9 KB per value at the pin on arm64
# macOS, about fifteen times less with the patch, A4 of
# audits/p0/wave1/5.1-mlir-analysis.md).
n=${1:?usage: many-values.sh N}
awk -v n="$n" 'BEGIN {
  printf "func.func @chain(%%x: i32) -> i32 {\n  %%c = arith.constant 1 : i32\n"
  printf "  %%v0 = arith.addi %%x, %%c : i32\n"
  for (i = 1; i < n; i++) printf "  %%v%d = arith.addi %%v%d, %%c : i32\n", i, i - 1
  printf "  return %%v%d : i32\n}\n", n - 1
}'
