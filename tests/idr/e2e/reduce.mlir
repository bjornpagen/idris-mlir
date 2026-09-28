// RUN: printf '#!/bin/sh\nif grep -q idr.str.append "$1"; then exit 1; fi\nexit 0\n' > %t.test
// RUN: chmod +x %t.test
// RUN: idris-mlir-reduce %s --reduction-tree="traversal-mode=0 test=%t.test" -o %t.reduced 2> %t.log
// RUN: FileCheck %s < %t.reduced
// rule: DRV-OPT-1
// idris-mlir-reduce is mlir-reduce with the idr dialect: it shrinks a module
// to what keeps a test interesting (14-testing.md), here any
// idr.str.append.
// CHECK: func.func private @twice
// CHECK-NEXT: idr.str.append
// CHECK-NOT: @fact
module {
  func.func private @fact(%n: i64) -> i64 attributes {idr.total} {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %one = arith.constant 1 : i64
      idr.yield %one : i64
    }
    default {
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %f = func.call @fact(%m) : (i64) -> i64
      %p = arith.muli %n, %f : i64
      idr.yield %p : i64
    }
    }
    return %r : i64
  }
  func.func private @twice(%s: !idr.str) -> !idr.str attributes {idr.total} {
    %r = idr.str.append %s, %s
    return %r : !idr.str
  }
}
