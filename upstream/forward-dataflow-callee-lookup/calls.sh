#!/bin/sh
# calls.sh N: a module of N functions, each calling the next, on standard
# output. Every function but the first is private, so an interprocedural
# analysis follows the calls.
n=${1:?usage: calls.sh N}
awk -v n="$n" 'BEGIN {
  printf "module {\n"
  for (i = 0; i < n - 1; i++) {
    printf "  func.func %s@f%d(%%x: i32) -> i32 {\n", (i == 0 ? "" : "private "), i
    printf "    %%r = func.call @f%d(%%x) : (i32) -> i32\n", i + 1
    printf "    return %%r : i32\n  }\n"
  }
  printf "  func.func private @f%d(%%x: i32) -> i32 {\n", n - 1
  printf "    %%c = arith.constant 7 : i32\n    return %%c : i32\n  }\n}\n"
}'
