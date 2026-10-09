// RUN: idris-mlir-opt %s --idr-isolate > %t.mlir
// RUN: FileCheck %s --check-prefix=OUTER < %t.mlir
// RUN: FileCheck %s --check-prefix=BODY < %t.mlir
// A constant the body uses is code the function rebuilds, not a value the
// closure carries: it is cloned into the function, and only the parameter
// it uses from above is captured. The function is total whether or not the
// enclosing one is, and breaks last only when that one does.
// OUTER-LABEL: func.func private @Main.scale(
// OUTER-SAME: %[[X:[^:]*]]: i64)
// OUTER: idr.closure @Main.scale$lam{{[0-9]+}}(%[[X]]) : (i64) -> !idr.fn<(i64) -> (!idr.str)>
// BODY: func.func private @Main.scale$lam{{[0-9]+}}(%[[CX:[^:]*]]: i64, %[[Y:[^:]*]]: i64) -> !idr.str
// BODY-SAME: attributes {idr.total}
// BODY-DAG: %[[K:.*]] = arith.constant 3 : i64
// BODY-DAG: idr.constant "scaled" : !idr.str
// BODY: arith.muli %[[K]], %[[Y]] : i64
// BODY: return
module {
  func.func private @Main.scale(%x: i64) -> !idr.fn<(i64) -> (!idr.str)> {
    %k = arith.constant 3 : i64
    %s = idr.constant "scaled" : !idr.str
    %f = idr.lambda : !idr.fn<(i64) -> (!idr.str)> {
    ^bb0(%y: i64):
      %a = arith.muli %k, %y : i64
      %b = arith.addi %a, %x : i64
      %t = idr.str.show signed %b : i64
      %u = idr.str.append %s, %t
      idr.yield %u : !idr.str
    }
    return %f : !idr.fn<(i64) -> (!idr.str)>
  }
  func.func @Main.main(%w: !idr.world) -> !idr.world {
    %one = arith.constant 1 : i64
    %f = func.call @Main.scale(%one) : (i64) -> !idr.fn<(i64) -> (!idr.str)>
    %s = idr.apply %f(%one) : !idr.fn<(i64) -> (!idr.str)>
    %w1 = idr.io.put_str %s, %w
    return %w1 : !idr.world
  }
}
