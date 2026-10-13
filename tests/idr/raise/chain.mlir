// RUN: idris-mlir-opt %s --idr-specialize > %t.mlir
// RUN: FileCheck %s < %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-specialize > %t2.mlir
// RUN: diff %t.mlir %t2.mlir
// A call whose result is applied, and that result applied again: both
// applies move into the callee in one run, so the call is one call of a
// clone taking both arguments. One raise per run would leave the second
// apply in the caller for the next run of the pass, and in the simplify
// loop one apply per round.
// CHECK-LABEL: idr.func private @use(
// CHECK-SAME: %[[N:[a-z0-9_]+]]: i64, %[[X:[a-z0-9_]+]]: i64, %[[Y:[a-z0-9_]+]]: i64)
// CHECK-NEXT: %[[R:.*]] = {{(idr\.)?}}call @[[MK:mk\.raise[0-9]+\.raise[0-9]+]](%[[N]], %[[X]], %[[Y]]) : (i64, i64, i64) -> i64
// CHECK-NEXT: return %[[R]]
// CHECK-NOT: {{(idr\.| )apply }}
// CHECK: idr.func private @[[MK]](
module attributes {idr.program} {
  idr.func private @add(%a: i64, %x: i64) -> i64 attributes {total} {
    %y = arith.addi %a, %x : i64
    return %y : i64
  }
  idr.func private @curry(%a: i64, %x: i64) -> !idr.fn<(i64) -> i64> attributes {total} {
    %s = arith.addi %a, %x : i64
    %f = idr.closure @add(%s) : (i64) -> !idr.fn<(i64) -> i64>
    return %f : !idr.fn<(i64) -> i64>
  }
  idr.func private @mk(%a: i64) -> !idr.fn<(i64) -> !idr.fn<(i64) -> i64>> attributes {total} {
    %f = idr.closure @curry(%a) : (i64) -> !idr.fn<(i64) -> !idr.fn<(i64) -> i64>>
    return %f : !idr.fn<(i64) -> !idr.fn<(i64) -> i64>>
  }
  idr.func private @use(%n: i64, %x: i64, %y: i64) -> i64 attributes {total} {
    %f = idr.call @mk(%n) : (i64) -> !idr.fn<(i64) -> !idr.fn<(i64) -> i64>>
    %g = idr.apply %f(%x) : !idr.fn<(i64) -> !idr.fn<(i64) -> i64>>
    %r = idr.apply %g(%y) : !idr.fn<(i64) -> i64>
    return %r : i64
  }
  idr.func @Main.main() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}
