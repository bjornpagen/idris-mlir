// RUN: idris-mlir-opt %s --idr-isolate > %t.mlir
// RUN: FileCheck %s --check-prefix=OUTER < %t.mlir
// RUN: FileCheck %s --check-prefix=MIDDLE < %t.mlir
// RUN: FileCheck %s --check-prefix=INNER < %t.mlir
// RUN: FileCheck %s --check-prefix=NAMES --implicit-check-not=idr.lambda --implicit-check-not='lam{{[0-9]+}}$lam' < %t.mlir
// A lambda inside a lambda is isolated first, innermost first: when the
// outer body is isolated the inner one is already a closure, of a function
// named after the definition both are in, and the outer body captures what
// that closure takes from above it. \a => \b => \c => a + b + c makes
// three functions: the innermost takes a and b, then c; the middle one
// takes a, then b, and makes the innermost's closure of the two; the
// definition makes the middle one's closure of a.
// OUTER-LABEL: func.func private @Main.add3(
// OUTER-SAME: %[[A:[^:]*]]: i64)
// OUTER-NEXT: %[[F:.*]] = idr.closure @Main.add3$lam{{[0-9]+}}(%[[A]]) : (i64) -> !idr.fn<(i64) -> !idr.fn<(i64) -> i64>>
// OUTER-NEXT: return %[[F]]
// MIDDLE: func.func private @Main.add3$lam{{[0-9]+}}(%[[A:[^:]*]]: i64, %[[B:[^:]*]]: i64) -> !idr.fn<(i64) -> i64>
// MIDDLE-NEXT: %[[G:.*]] = idr.closure @Main.add3$lam{{[0-9]+}}(%[[A]], %[[B]]) : (i64, i64) -> !idr.fn<(i64) -> i64>
// MIDDLE-NEXT: return %[[G]]
// INNER: func.func private @Main.add3$lam{{[0-9]+}}(%[[A:[^:]*]]: i64, %[[B:[^:]*]]: i64, %[[C:[^:]*]]: i64) -> i64
// INNER-NEXT: %[[AB:.*]] = arith.addi %[[A]], %[[B]] : i64
// INNER-NEXT: %[[ABC:.*]] = arith.addi %[[AB]], %[[C]] : i64
// INNER-NEXT: return %[[ABC]]
// NAMES: func.func @Main.main(
module {
  func.func private @Main.add3(%a: i64) -> !idr.fn<(i64) -> (!idr.fn<(i64) -> (i64)>)> {
    %f = idr.lambda : !idr.fn<(i64) -> (!idr.fn<(i64) -> (i64)>)> {
    ^bb0(%b: i64):
      %g = idr.lambda : !idr.fn<(i64) -> (i64)> {
      ^bb0(%c: i64):
        %ab = arith.addi %a, %b : i64
        %abc = arith.addi %ab, %c : i64
        idr.yield %abc : i64
      }
      idr.yield %g : !idr.fn<(i64) -> (i64)>
    }
    return %f : !idr.fn<(i64) -> (!idr.fn<(i64) -> (i64)>)>
  }
  func.func @Main.main(%w: !idr.world) -> !idr.world {
    %one = arith.constant 1 : i64
    %f = func.call @Main.add3(%one) : (i64) -> !idr.fn<(i64) -> (!idr.fn<(i64) -> (i64)>)>
    %g = idr.apply %f(%one) : !idr.fn<(i64) -> (!idr.fn<(i64) -> (i64)>)>
    %r = idr.apply %g(%one) : !idr.fn<(i64) -> (i64)>
    %w1 = idr.io.put_int signed %r, %w : i64
    return %w1 : !idr.world
  }
}
