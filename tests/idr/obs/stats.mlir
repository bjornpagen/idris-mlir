// RUN: idris-mlir-cc %s --check --stats 2> %t.stats
// RUN: FileCheck %s < %t.stats
// RUN: idris-mlir-cc %s --check 2> %t.quiet
// RUN: FileCheck %s --check-prefix=QUIET --allow-empty < %t.quiet
// --stats prints the statistics of every step's passes. The simplify loop
// shows those of the passes its rounds run, which the pass manager never
// prints, as its own, `<pass>.<statistic>`, after the rounds it ran.
// Without --stats, nothing.
// CHECK: Pass statistics report
// CHECK: IdrSimplify
// CHECK-DAG: (S) {{ *[0-9]+}} idr-canonicalize.rewrites - Rewrites by patterns
// CHECK-DAG: (S) {{ *[0-9]+}} idr-eval.cache-hits -
// CHECK-DAG: (S) {{ *[0-9]+}} idr-eval.evaluated - Calls replaced by their results
// CHECK-DAG: (S) {{ *[0-9]+}} idr-loop-breakers.breakers -
// CHECK-DAG: (S) {{ *[1-9][0-9]*}} rounds - Rounds run
// CHECK: IdrDefunctionalize
// CHECK-DAG: (S) {{ *[0-9]+}} closures - Keys whose closures stay closures
// CHECK-DAG: (S) {{ *[0-9]+}} sums - Keys whose closures became sums
// QUIET-NOT: statistics
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
