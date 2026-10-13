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
// CHECK-LABEL: idr.func private @pick(
// CHECK-SAME: -> !idr.fn<(i64) -> i64> attributes {total}
// CHECK-LABEL: idr.func private @use(
// CHECK-SAME: %[[N:[a-z0-9_]+]]: i64, %[[X:[a-z0-9_]+]]: i64)
// CHECK: %[[Y:.*]] = arith.addi %[[X]]
// CHECK-NEXT: %[[R:.*]] = {{(idr\.)?}}call @[[PICK:pick\.raise[0-9]+]](%[[N]], %[[Y]]) : (i64, i64) -> i64
// CHECK-NEXT: return %[[R]]
// CHECK-NOT: {{(idr\.| )apply }}
// CHECK: idr.func private @[[PICK]](
// CHECK-SAME: %[[A:[a-z0-9_]+]]: i64, %[[B:[a-z0-9_]+]]: i64) -> i64
// CHECK-SAME: total
// CHECK-NEXT: %[[M:.*]] = {{(idr\.)?}}match_lit %[[A]] : i64 -> (i64) {
// CHECK-NEXT: case 0 {
// CHECK-NEXT: %[[S:.*]] = {{(idr\.)?}}call @sub(%[[A]], %[[B]]) : (i64, i64) -> i64
// CHECK-NEXT: idr.yield %[[S]] : i64
// CHECK: default {
// CHECK-NEXT: %[[P:.*]] = {{(idr\.)?}}call @add(%[[A]], %[[B]]) : (i64, i64) -> i64
// CHECK-NEXT: idr.yield %[[P]] : i64
// CHECK: return %[[M]] : i64
// CHECK-NOT: {{(idr\.| )apply }}
module attributes {idr.program} {
  idr.func private @add(%a: i64, %x: i64) -> i64 attributes {total} {
    %y = arith.addi %a, %x : i64
    return %y : i64
  }
  idr.func private @sub(%a: i64, %x: i64) -> i64 attributes {total} {
    %y = arith.subi %a, %x : i64
    return %y : i64
  }
  idr.func private @pick(%a: i64) -> !idr.fn<(i64) -> (i64)> attributes {total} {
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
  idr.func private @use(%n: i64, %x: i64) -> i64 attributes {total} {
    %f = idr.call @pick(%n) : (i64) -> !idr.fn<(i64) -> (i64)>
    %c1 = arith.constant 1 : i64
    %y = arith.addi %x, %c1 : i64
    %r = idr.apply %f(%y) : !idr.fn<(i64) -> (i64)>
    return %r : i64
  }
  idr.func @Main.main() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}
