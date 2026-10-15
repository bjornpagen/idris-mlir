// RUN: idris-mlir -c %s -o %t.o --stats 2> %t.stats
// RUN: FileCheck %s < %t.stats
// RUN: idris-mlir -c %s -o %t.quiet.o 2> %t.quiet
// RUN: FileCheck %s --check-prefix=QUIET --allow-empty < %t.quiet
// NEEDS-ACCEPTANCE: the statistics' descriptions, as C12 declares them.
// --stats prints the statistics of every pass of the driver's manager: the
// functions contified under IdrContify, the calls inlined and the nodes
// made under IdrOptimize, the sums under IdrDefunctionalize. Without
// --stats, nothing.
// CHECK: Pass statistics report
// CHECK-DAG: IdrContify
// CHECK-DAG: (S) {{ *[0-9]+}} contified -
// CHECK-DAG: IdrOptimize
// CHECK-DAG: (S) {{ *[0-9]+}} inlined -
// CHECK-DAG: (S) {{ *[0-9]+}} nodes -
// CHECK-DAG: IdrDefunctionalize
// CHECK-DAG: (S) {{ *[0-9]+}} boxed -
// CHECK-DAG: (S) {{ *[0-9]+}} sums -
// QUIET-NOT: statistics
module {
  idr.func private @fact(%n: i64) -> i64 attributes {total} {
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
  idr.func @Prog.main(%w: !idr.world) -> !idr.world {
    %ten = arith.constant 10 : i64
    %f = idr.call @fact(%ten) : (i64) -> i64
    %w1 = idr.io.put_int signed %f, %w : i64
    %nl = arith.constant 10 : i32
    %w2 = idr.io.put_char %nl, %w1
    return %w2 : !idr.world
  }
}
