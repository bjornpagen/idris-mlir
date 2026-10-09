// RUN: idris-mlir-opt %s --idr-specialize > %t.mlir
// RUN: FileCheck %s < %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-specialize > %t2.mlir
// RUN: diff %t.mlir %t2.mlir
// A call whose result is applied at once, with only an op without effects
// between them: the call and the apply become one call of a clone of the
// callee that also takes the apply's argument. In the clone, the apply
// moves into both regions of the match that the callee returns, where it
// meets the closure each region builds and becomes a call. Every tail
// applies a known closure of a total function, and the callee is total, so
// the clone is total. A second run changes nothing.
// CHECK-LABEL: func.func private @pick(
// CHECK-SAME: -> !idr.fn<(i64) -> i64> attributes {idr.total}
// CHECK-LABEL: func.func private @use(
// CHECK-SAME: %[[N:[a-z0-9_]+]]: i64, %[[X:[a-z0-9_]+]]: i64)
// CHECK: %[[Y:.*]] = arith.addi %[[X]]
// CHECK-NEXT: %[[R:.*]] = call @[[PICK:pick\$raise\$[0-9]+]](%[[N]], %[[Y]]) : (i64, i64) -> i64
// CHECK-NEXT: return %[[R]]
// CHECK-NOT: idr.apply
// CHECK: func.func private @[[PICK]](
// CHECK-SAME: %[[A:[a-z0-9_]+]]: i64 {{.*}}, %[[B:[a-z0-9_]+]]: i64 {{.*}}) -> i64
// CHECK-SAME: idr.total
// CHECK-NEXT: %[[M:.*]] = idr.match_lit %[[A]] : i64 -> (i64) {
// CHECK-NEXT: case 0 {
// CHECK-NEXT: %[[S:.*]] = func.call @sub(%[[A]], %[[B]]) : (i64, i64) -> i64
// CHECK-NEXT: idr.yield %[[S]] : i64
// CHECK: default {
// CHECK-NEXT: %[[P:.*]] = func.call @add(%[[A]], %[[B]]) : (i64, i64) -> i64
// CHECK-NEXT: idr.yield %[[P]] : i64
// CHECK: return %[[M]] : i64
// CHECK-NOT: idr.apply
module attributes {idr.program} {
  func.func private @add(%a: i64, %x: i64) -> i64 attributes {idr.total} {
    %y = arith.addi %a, %x : i64
    return %y : i64
  }
  func.func private @sub(%a: i64, %x: i64) -> i64 attributes {idr.total} {
    %y = arith.subi %a, %x : i64
    return %y : i64
  }
  func.func private @pick(%a: i64) -> !idr.fn<(i64) -> (i64)> attributes {idr.total} {
    %r = idr.match_lit %a : i64 -> (!idr.fn<(i64) -> (i64)>) {
    case 0 {
      %f = idr.closure @sub(%a) : (i64) -> !idr.fn<(i64) -> (i64)>
      idr.yield %f : !idr.fn<(i64) -> (i64)>
    }
    default {
      %f = idr.closure @add(%a) : (i64) -> !idr.fn<(i64) -> (i64)>
      idr.yield %f : !idr.fn<(i64) -> (i64)>
    }
    }
    return %r : !idr.fn<(i64) -> (i64)>
  }
  func.func private @use(%n: i64, %x: i64) -> i64 attributes {idr.total} {
    %f = func.call @pick(%n) : (i64) -> !idr.fn<(i64) -> (i64)>
    %c1 = arith.constant 1 : i64
    %y = arith.addi %x, %c1 : i64
    %r = idr.apply %f(%y) : !idr.fn<(i64) -> (i64)>
    return %r : i64
  }
  func.func @Main.main() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}
