#!/bin/sh
# nested-regions.sh DEPTH: a function whose body nests scf.execute_region
# DEPTH deep, on standard output. Each kind of analysis on upstream's
# data-flow framework initializes over it with a native frame per level at
# the pin: sparse forward (`mlir-opt -sccp`, `-int-range-optimizations`),
# sparse backward (`-remove-dead-values`, through liveness) and dense
# (`-test-last-modified`, `-test-next-access`, upstream's test passes).
# Under a small stack (`ulimit -s 256`), a few thousand levels overflow
# them without the patch and finish with it (conjecture on the depth: no
# overflowing depth is measured), once the parser, dead-code analysis and
# the symbol-table walk no longer recurse first (the patch's unit test
# builds the nest in memory).
depth=${1:?usage: nested-regions.sh DEPTH}
awk -v n="$depth" 'BEGIN {
  printf "func.func @nested(%%x: i32) -> i32 {\n"
  for (i = 0; i < n; i++) printf "%%r%d = scf.execute_region -> i32 {\n", i
  printf "scf.yield %%x : i32\n"
  for (i = n - 1; i >= 0; i--) {
    printf "}\n"
    if (i > 0) printf "scf.yield %%r%d : i32\n", i
  }
  printf "return %%r0 : i32\n}\n"
}'
