#!/bin/sh
# nested-module.sh DEPTH: a module of unregistered operations nested DEPTH
# deep, each in the one block of the one region of the one before it, in
# the generic form, on standard output (read it with
# -allow-unregistered-dialect). Any run of mlir-opt destroys the module
# when it ends; at the pin destruction takes native frames per level of
# nesting, and each region's destructor drops the references of all below
# it again, so on a small stack (`ulimit -s 256`) a few thousand levels
# overflow it (conjecture on the depth: no overflowing depth is measured).
# The textual parser and printer recurse on the same depth through the
# operations' parse and print hooks, so through mlir-opt destruction is
# seen alone only on IR read from bytecode and not printed back, or built
# in memory, as the patch's unit test does.
depth=${1:?usage: nested-module.sh DEPTH}
awk -v n="$depth" 'BEGIN {
  for (i = 1; i < n; i++) printf "\"test.nest\"() ({\n"
  printf "\"test.leaf\"() : () -> ()\n"
  for (i = 1; i < n; i++) printf "}) : () -> ()\n"
}'
