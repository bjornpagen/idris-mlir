#!/bin/sh
# nested-regions.sh DEPTH: a function whose body nests scf.execute_region
# DEPTH deep, on standard output. `mlir-opt -sccp` on it loads dead-code
# analysis, whose initialization recursed once per level at the pin: run
# under a small stack (`ulimit -s 256`), a few thousand levels overflow it
# without the patch and finish with it (conjecture on the depth: no
# overflowing depth is measured).
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
