#!/bin/sh
# nested-callables.sh DEPTH: a module of one function whose body nests
# scf.execute_region DEPTH deep around a call, on standard output.
# `mlir-opt -inline` builds the call graph, whose construction recursed once
# per level at the pin: under a small stack (`ulimit -s 256`), a few
# thousand levels overflow it without the patch and finish with it
# (conjecture on the depth).
depth=${1:?usage: nested-callables.sh DEPTH}
awk -v n="$depth" 'BEGIN {
  printf "func.func private @leaf(%%x: i32) -> i32 {\n  return %%x : i32\n}\n"
  printf "func.func @nested(%%x: i32) -> i32 {\n"
  for (i = 0; i < n; i++) printf "%%r%d = scf.execute_region -> i32 {\n", i
  printf "%%c = func.call @leaf(%%x) : (i32) -> i32\nscf.yield %%c : i32\n"
  for (i = n - 1; i >= 0; i--) {
    printf "}\n"
    if (i > 0) printf "scf.yield %%r%d : i32\n", i
  }
  printf "return %%r0 : i32\n}\n"
}'
