#!/bin/sh
# nested-callee.sh DEPTH: a module whose private function nests
# scf.execute_region DEPTH deep and is called once, on standard output.
# `mlir-opt -inline` on it clones the callee's body into the caller; at the
# pin the clone takes native frames per level of nesting, so on a small
# stack (`ulimit -s 256`) a few thousand levels overflow it (conjecture on
# the depth: no overflowing depth is measured). The textual parser and
# printer recurse on the same depth through the operations' parse and print
# hooks, so through mlir-opt the clone is seen alone only on IR read from
# bytecode and not printed back, or built in memory, as the patch's unit
# test does.
depth=${1:?usage: nested-callee.sh DEPTH}
awk -v n="$depth" 'BEGIN {
  printf "func.func private @callee() {\n"
  for (i = 0; i < n; i++) printf "scf.execute_region {\n"
  for (i = 0; i < n; i++) printf "scf.yield\n}\n"
  printf "return\n}\n"
  printf "func.func @caller() {\nfunc.call @callee() : () -> ()\nreturn\n}\n"
}'
