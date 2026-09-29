// RUN: idris-mlir-opt %s --idr-defunctionalize > %t.mlir
// RUN: FileCheck %s < %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=no-closures -o /dev/null
// A function picked at runtime between two labels, one with a capture: the
// closure type becomes a sum with a constructor per label, whose fields are
// the captures, and the application a match that calls the label. What is
// left is no closure.
// CHECK: idr.data @[[F0:fn\$[0-9]+]] {
// CHECK-NEXT: idr.ctor @add tag 0 (i64)
// CHECK-NEXT: idr.ctor @dbl tag 1 ()
// CHECK-NEXT: }
// CHECK-NOT: !idr.fn
module attributes {idr.program} {
  func.func private @add(%a: i64, %x: i64) -> i64 attributes {idr.total} {
    %y = arith.addi %a, %x : i64
    return %y : i64
  }
  func.func private @dbl(%x: i64) -> i64 attributes {idr.total} {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  // CHECK-LABEL: func.func private @pick(
  // CHECK-SAME: -> !idr.data<@[[F0]]>
  // CHECK: idr.con @[[F0]]::@add(%{{.*}}) : (i64) -> !idr.data<@[[F0]]>
  // CHECK: idr.con @[[F0]]::@dbl() : () -> !idr.data<@[[F0]]>
  func.func private @pick(%n: i64) -> !idr.fn<(i64) -> (i64)> attributes {idr.total} {
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
  // CHECK-LABEL: func.func @Main.main(
  // CHECK: %[[F:.*]] = call @pick(%[[N:.*]]) : (i64) -> !idr.data<@[[F0]]>
  // CHECK: idr.match %[[F]] : !idr.data<@[[F0]]> -> (i64) {
  // CHECK-NEXT: case @add(%[[A:.*]]: i64) {
  // CHECK-NEXT: %[[R:.*]] = {{(func.)?}}call @add(%[[A]], %[[N]]) : (i64, i64) -> i64
  // CHECK-NEXT: idr.yield %[[R]] : i64
  // CHECK: case @dbl() {
  // CHECK-NEXT: %[[S:.*]] = {{(func.)?}}call @dbl(%[[N]]) : (i64) -> i64
  // CHECK-NEXT: idr.yield %[[S]] : i64
  func.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_char %w
    %n = arith.extui %c : i32 to i64
    %f = call @pick(%n) : (i64) -> !idr.fn<(i64) -> (i64)>
    %r = idr.apply %f(%n) : !idr.fn<(i64) -> (i64)>
    %w2 = idr.io.put_int signed %r, %w1 : i64
    return %w2 : !idr.world
  }
}
