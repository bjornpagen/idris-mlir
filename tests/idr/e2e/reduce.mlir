// RUN: printf '#!/bin/sh\nif grep -q idr.str.append "$1"; then exit 1; fi\nexit 0\n' > %t.test
// RUN: chmod +x %t.test
// RUN: idris-mlir-reduce %s --reduction-tree="traversal-mode=0 test=%t.test" -o %t.reduced 2> %t.log
// RUN: FileCheck %s < %t.reduced
// idris-mlir-reduce is mlir-reduce with the idr dialect: it shrinks a module
// to what keeps a test interesting, here any
// idr.str.append.
// CHECK: idr.func @twice
// CHECK-NEXT: idr.str.append
// CHECK-NOT: @fact
idr.program @reduce root(@root) stage(first) {
  idr.func @fact(%n: i64) -> i64 attributes {total} {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %one = arith.constant 1 : i64
      idr.yield %one : i64
    }
    default {
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %f = idr.call @fact(%m) : (i64) -> i64
      %p = arith.muli %n, %f : i64
      idr.yield %p : i64
    }
    }
    return %r : i64
  }
  idr.func @twice(%s: !idr.str) -> !idr.str attributes {total} {
    %r = idr.str.append %s, %s
    return %r : !idr.str
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
