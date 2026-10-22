#!/bin/sh
# nested-tables.sh DEPTH: a module nesting builtin.module DEPTH deep around
# a private function, on standard output. `mlir-opt -inline` builds the
# inliner's use lists, which walk the symbol tables, and that walk recursed
# once per level at the pin: under a small stack (`ulimit -s 256`), a few
# thousand levels overflow it without the patch and finish with it
# (conjecture on the depth: no overflowing depth is measured). The textual
# parser recurses on the same depth through each operation's parse hook, so
# the walk alone is seen only on IR read from bytecode, or built in memory,
# as the patch's unit test does.
depth=${1:?usage: nested-tables.sh DEPTH}
awk -v n="$depth" 'BEGIN {
  for (i = 0; i < n; i++) printf "module {\n"
  printf "func.func private @leaf(%%x: i32) -> i32 {\n  return %%x : i32\n}\n"
  for (i = 0; i < n; i++) printf "}\n"
}'
