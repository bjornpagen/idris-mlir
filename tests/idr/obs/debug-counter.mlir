// RUN: mkdir -p %t.dumps
// RUN: idris-mlir -c %s -o %t.o --dump-dir=%t.dumps
// RUN: cat %t.dumps/*-idr-simplify.mlir | FileCheck %s --check-prefix=LEFT
// RUN: %cc %t.o -o %t
// RUN: %t | FileCheck %s --check-prefix=OUT
// idr-eval is not in the simplify round, so the closed call of @fact stays
// and runs at run time.
// LEFT: func.call @fact(
// OUT: 3628800
module attributes {idr.program} {
  func.func private @fact(%n: i64) -> i64 attributes {idr.total, no_inline} {
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
  func.func @Prog.main(%w: !idr.world) -> !idr.world {
    %ten = arith.constant 10 : i64
    %f = func.call @fact(%ten) : (i64) -> i64
    %w1 = idr.io.put_int signed %f, %w : i64
    %nl = arith.constant 10 : i32
    %w2 = idr.io.put_char %nl, %w1
    return %w2 : !idr.world
  }
}
