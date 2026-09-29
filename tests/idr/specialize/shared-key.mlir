// RUN: idris-mlir-opt %s --idr-specialize > %t.mlir
// RUN: FileCheck %s < %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-specialize > %t2.mlir
// RUN: diff %t.mlir %t2.mlir
// Calls whose keys are equal share one clone: @apply is on no cycle, so it
// specializes on the closure it is given, whose label is static and whose
// capture is a runtime leaf. The first two calls pass closures of @add over
// different values, one key; the third a closure of @sub, another key. A
// second run finds the clones by their keys and changes nothing.
// CHECK-LABEL: func.func private @use(
// CHECK: call @[[ADD:apply\$spec\$[0-9]+]](%{{.*}}, %{{.*}}) : (i64, i64) -> i64
// CHECK-NEXT: call @[[ADD]](%{{.*}}, %{{.*}}) : (i64, i64) -> i64
// CHECK-NEXT: call @[[SUB:apply\$spec\$[0-9]+]](%{{.*}}, %{{.*}}) : (i64, i64) -> i64
// CHECK-NOT: call @[[ADD]]
// CHECK: func.func private @[[ADD]](
// CHECK: call @add(
// CHECK: func.func private @[[SUB]](
// CHECK: call @sub(
// CHECK-NOT: func.func private @apply$spec$
module attributes {idr.program} {
  func.func private @add(%a: i64 {idr.quantity = "w"}, %x: i64 {idr.quantity = "w"}) -> i64 attributes {idr.total} {
    %y = arith.addi %a, %x : i64
    return %y : i64
  }
  func.func private @sub(%a: i64 {idr.quantity = "w"}, %x: i64 {idr.quantity = "w"}) -> i64 attributes {idr.total} {
    %y = arith.subi %a, %x : i64
    return %y : i64
  }
  func.func private @apply(%f: !idr.fn<(i64) -> (i64)> {idr.quantity = "w"}, %x: i64 {idr.quantity = "w"}) -> i64 attributes {idr.total} {
    %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    return %y : i64
  }
  func.func private @use(%n: i64 {idr.quantity = "w"}, %m: i64 {idr.quantity = "w"}, %x: i64 {idr.quantity = "w"}) -> i64 attributes {idr.total} {
    %f = idr.closure @add(%n) : (i64) -> !idr.fn<(i64) -> (i64)>
    %g = idr.closure @add(%m) : (i64) -> !idr.fn<(i64) -> (i64)>
    %h = idr.closure @sub(%n) : (i64) -> !idr.fn<(i64) -> (i64)>
    %r1 = func.call @apply(%f, %x) : (!idr.fn<(i64) -> (i64)>, i64) -> i64
    %r2 = func.call @apply(%g, %x) : (!idr.fn<(i64) -> (i64)>, i64) -> i64
    %r3 = func.call @apply(%h, %x) : (!idr.fn<(i64) -> (i64)>, i64) -> i64
    %s = arith.addi %r1, %r2 : i64
    %t = arith.addi %s, %r3 : i64
    return %t : i64
  }
  func.func @Main.main() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}
