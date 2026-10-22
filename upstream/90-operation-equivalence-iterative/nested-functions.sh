#!/bin/sh
# nested-functions.sh DEPTH: a module of two private functions alike, each
# nesting scf.execute_region DEPTH deep around a constant it yields back
# out, on standard output. `mlir-opt -duplicate-function-elimination`
# compares their bodies with OperationEquivalence::isRegionEquivalentTo,
# which at the pin calls itself through isEquivalentTo once per level, so on
# a small stack (`ulimit -s 256`) a few thousand levels overflow it
# (conjecture on the depth: no overflowing depth is measured). The textual
# parser and printer recurse on the same depth through the operations' parse
# and print hooks, so through mlir-opt the comparison is seen alone only on
# IR read from bytecode and not printed back, or built in memory, as the
# patch's unit test does.
depth=${1:?usage: nested-functions.sh DEPTH}
awk -v n="$depth" 'BEGIN {
  for (f = 0; f < 2; f++) {
    printf "func.func private @f%d() -> i32 {\n", f
    for (i = 0; i < n; i++) printf "%%r%d = scf.execute_region -> i32 {\n", i
    printf "%%c = arith.constant 0 : i32\nscf.yield %%c : i32\n"
    for (i = n - 1; i > 0; i--) printf "}\nscf.yield %%r%d : i32\n", i
    printf "}\nreturn %%r0 : i32\n}\n"
  }
}'
