// RUN: idris-mlir-opt %s --idr-isolate > %t.mlir
// RUN: FileCheck %s --check-prefix=OUTER --implicit-check-not=idr.delay < %t.mlir
// RUN: FileCheck %s --check-prefix=LATER < %t.mlir
// RUN: FileCheck %s --check-prefix=NEVER < %t.mlir
// The body of an idr.delay becomes a private function of its own,
// `<f>$delay<n>`, and the delay an idr.suspend of it over the values the
// body uses from above, which the function takes as its only parameters. It
// returns the suspension's value, cloning the constants it uses. A body
// that never returns, a crash, still has that result.
// OUTER-LABEL: func.func private @Main.later(
// OUTER-SAME: %[[X:[^:]*]]: i64)
// OUTER: idr.suspend @Main.later$delay{{[0-9]+}}(%[[X]]) : (i64) -> !idr.lazy<i64>
// OUTER: idr.suspend @Main.later$delay{{[0-9]+}}() : () -> !idr.lazy<i64>
// LATER: func.func private @Main.later$delay{{[0-9]+}}(%[[X:[^:]*]]: i64) -> i64
// LATER-SAME: attributes {idr.total}
// LATER-NEXT: %[[K:.*]] = arith.constant 2 : i64
// LATER-NEXT: %[[Y:.*]] = arith.muli %[[X]], %[[K]] : i64
// LATER-NEXT: return %[[Y]] : i64
// NEVER-LABEL: func.func private @Main.later$delay{{[0-9]+}}() -> i64
// NEVER-NEXT: idr.crash "never"
// NEVER-NEXT: ub.unreachable
module {
  func.func private @Main.later(%x: i64) -> (!idr.lazy<i64>, !idr.lazy<i64>) {
    %k = arith.constant 2 : i64
    %t = idr.delay : !idr.lazy<i64> {
      %y = arith.muli %x, %k : i64
      idr.yield %y : i64
    }
    %u = idr.delay : !idr.lazy<i64> {
      idr.crash "never"
      ub.unreachable
    }
    return %t, %u : !idr.lazy<i64>, !idr.lazy<i64>
  }
  func.func @Main.main(%w: !idr.world) -> !idr.world {
    %one = arith.constant 1 : i64
    %t:2 = func.call @Main.later(%one) : (i64) -> (!idr.lazy<i64>, !idr.lazy<i64>)
    %v = idr.force %t#0 : !idr.lazy<i64> -> i64
    %w1 = idr.io.put_int signed %v, %w : i64
    return %w1 : !idr.world
  }
}
