// RUN: idris-mlir -c %s -o %t.o --stats 2> %t.stats
// RUN: FileCheck %s < %t.stats
// RUN: idris-mlir -c %s -o %t.quiet.o 2> %t.quiet
// RUN: FileCheck %s --check-prefix=QUIET --allow-empty < %t.quiet
// RUN: idris-mlir-opt %s --idr-contify --idr-simplify --remarks-filter=idr-simplify -o /dev/null 2> %t.remarks
// RUN: FileCheck %s --check-prefix=ROUND < %t.remarks
// --stats prints the statistics of every pass of the driver's manager: the
// rounds of the simplify loop under IdrSimplify, the functions contified
// under IdrContify, the keys under IdrDefunctionalize. The passes a round
// runs are not the manager's, so it never prints theirs: the loop's
// statistics remark reports them after the rounds it ran, each as
// `<pass>.<statistic>=<total>`. Without --stats, nothing.
// CHECK: Pass statistics report
// CHECK-DAG: IdrContify
// CHECK-DAG: (S) {{ *[0-9]+}} contified - Functions inlined into their one caller
// CHECK-DAG: IdrSimplify
// CHECK-DAG: (S) {{ *[1-9][0-9]*}} rounds - Rounds run
// CHECK-DAG: IdrDefunctionalize
// CHECK-DAG: (S) {{ *[0-9]+}} boxed - Records and closure sums made boxes so that the cells holding them fit
// CHECK-DAG: (S) {{ *[0-9]+}} closures - Keys whose closures stay closures
// CHECK-DAG: (S) {{ *[0-9]+}} sums - Keys whose closures became sums
// QUIET-NOT: statistics
// ROUND: remark: [Analysis] statistics {{.*}}Category:idr-simplify
// ROUND-SAME: idr-loop-breakers.breakers={{[0-9]+}}
module attributes {idr.program} {
  idr.func private @fact(%n: i64) -> i64 attributes {total, no_inline} {
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
