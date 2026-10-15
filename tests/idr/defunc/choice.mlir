// RUN: idris-mlir-opt %s --idr-defunctionalize > %t.mlir
// RUN: FileCheck %s < %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=no-closures -o /dev/null
// NEEDS-ACCEPTANCE: the sums' printed forms and the dispatches, as C01's printer and C06's conversion write them.
// A function picked at runtime between two labels, one with a capture: the
// closure type becomes a sum with a constructor per label, whose fields are
// the captures, and the application a match that calls the label. What is
// left is no closure.
// CHECK: ![[F0:[A-Za-z0-9_$.]+]] = !idr.data<{{[^,]*}}, closures [@add(i64), @dbl()]
// CHECK-NOT: !idr.fn
idr.program @choice root(@Main.main) stage(higher) {
  idr.func @add(%a: i64, %x: i64) -> i64 attributes {total} {
    %y = arith.addi %a, %x : i64
    return %y : i64
  }
  idr.func @dbl(%x: i64) -> i64 attributes {total} {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  // CHECK-LABEL: idr.func @pick(
  // CHECK-SAME: -> ![[F0]]
  // CHECK: con ![[F0]] @add(%{{.*}} : i64)
  // CHECK: con ![[F0]] @dbl()
  idr.func @pick(%n: i64) -> !idr.fn<(i64) -> (i64)> attributes {total} {
    %r = idr.match_lit %n : i64 -> (!idr.fn<(i64) -> (i64)>) {
    case 0 {
      %c1 = arith.constant 1 : i64
      %f = idr.closure @add(%c1) : (i64) -> !idr.fn<(i64) -> (i64)>
      idr.yield %f : !idr.fn<(i64) -> (i64)>
    }
    default {
      %g = idr.closure @dbl() : () -> !idr.fn<(i64) -> (i64)>
      idr.yield %g : !idr.fn<(i64) -> (i64)>
    }
    }
    return %r : !idr.fn<(i64) -> (i64)>
  }
  // CHECK-LABEL: idr.func @Main.main(
  // CHECK: %[[F:.*]] = call @pick(%[[N:.*]]) : (i64) -> ![[F0]]
  // CHECK: match %[[F]] : ![[F0]] -> (i64) {
  // CHECK-NEXT: case @add(%[[A:.*]]: i64) {
  // CHECK-NEXT: %[[R:.*]] = {{(idr\.)?}}call @add(%[[A]], %[[N]]) : (i64, i64) -> i64
  // CHECK-NEXT: idr.yield %[[R]] : i64
  // CHECK: case @dbl() {
  // CHECK-NEXT: %[[S:.*]] = {{(idr\.)?}}call @dbl(%[[N]]) : (i64) -> i64
  // CHECK-NEXT: idr.yield %[[S]] : i64
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %f = call @pick(%n) : (i64) -> !idr.fn<(i64) -> (i64)>
    %r = idr.apply %f(%n) : !idr.fn<(i64) -> (i64)>
    %w2 = idr.io.put_int signed %r, %w1 : i64
    return %w2 : !idr.world
  }
}
