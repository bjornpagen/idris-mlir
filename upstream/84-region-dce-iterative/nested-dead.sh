#!/bin/sh
# nested-dead.sh DEPTH: a function whose body nests scf.execute_region DEPTH
# deep, each level holding a dead addition, on standard output.
# `mlir-opt -expand-strided-metadata` on it runs the greedy pattern driver
# on the function, which runs region DCE after its round; at the pin its
# liveness propagation and its deletion each take native frames per level,
# so on a small stack (`ulimit -s 256`) a few thousand levels overflow it
# (conjecture on the depth: no overflowing depth is measured). The textual
# parser and printer recurse on the same depth through the operations'
# parse and print hooks, so region DCE alone is seen only on IR read from
# bytecode and not printed back, or built in memory.
depth=${1:?usage: nested-dead.sh DEPTH}
awk -v n="$depth" 'BEGIN {
  printf "func.func @nested(%%x: i32) -> i32 {\n"
  for (i = 0; i < n; i++) {
    printf "%%r%d = scf.execute_region -> i32 {\n", i
    printf "%%d%d = arith.addi %%x, %%x : i32\n", i
  }
  printf "scf.yield %%x : i32\n"
  for (i = n - 1; i >= 0; i--) {
    printf "}\n"
    if (i > 0) printf "scf.yield %%r%d : i32\n", i
  }
  printf "return %%r0 : i32\n}\n"
}'
