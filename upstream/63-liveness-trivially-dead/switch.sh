#!/bin/sh
# switch.sh CASES: a private function returning an scf.index_switch of
# CASES cases, each adding its constant to an argument, called from a
# public one, on standard output.
cases=${1:?usage: switch.sh CASES}
awk -v n="$cases" 'BEGIN {
  print "func.func private @f(%i: index, %x: i64) -> i64 {"
  print "  %r = scf.index_switch %i -> i64"
  for (k = 0; k < n; k++)
    printf "  case %d {\n    %%c = arith.constant %d : i64\n    %%t = arith.addi %%c, %%x : i64\n    scf.yield %%t : i64\n  }\n", k, k
  print "  default {\n    scf.yield %x : i64\n  }"
  print "  return %r : i64"
  print "}"
  print "func.func @main(%i: index, %x: i64) -> i64 {"
  print "  %r = func.call @f(%i, %x) : (index, i64) -> i64"
  print "  return %r : i64"
  print "}"
}'
