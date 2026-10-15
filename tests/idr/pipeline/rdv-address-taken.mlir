// RUN: idris-mlir-opt %s --remove-dead-values > %t.mlir
// RUN: FileCheck %s < %t.mlir
// @f is named by a closure, so remove-dead-values keeps its parameters,
// and finds %y, which @g passes to the parameter @f never reads, dead: the
// parameter of @g goes, and the call passes poison in its place. Raising
// and apply of a known closure make such calls.
// CHECK-LABEL: idr.func @g(
// CHECK-SAME: %[[X:[a-z0-9_]+]]: i64) -> i64
// CHECK-NEXT: %[[P:.*]] = ub.poison : i64
// CHECK-NEXT: %[[R:.*]] = call @f(%[[X]], %[[P]]) : (i64, i64) -> i64
// CHECK-NEXT: return %[[R]]
idr.program @"rdv-address-taken" root(@Main.main) stage(higher) {
  idr.func @f(%a: i64, %b: i64) -> i64 attributes {total} {
    return %a : i64
  }
  idr.func @g(%x: i64, %y: i64) -> i64 attributes {total} {
    %r = idr.call @f(%x, %y) : (i64, i64) -> i64
    return %r : i64
  }
  idr.func @h(%x: i64) -> !idr.fn<(i64) -> (i64)> attributes {total} {
    %c = idr.closure @f(%x) : (i64) -> !idr.fn<(i64) -> (i64)>
    return %c : !idr.fn<(i64) -> (i64)>
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %r = idr.call @g(%n, %n) : (i64, i64) -> i64
    %k = idr.call @h(%n) : (i64) -> !idr.fn<(i64) -> (i64)>
    %s = idr.apply %k(%r) : !idr.fn<(i64) -> (i64)>
    %w2 = idr.io.put_int signed %s, %w1 : i64
    return %w2 : !idr.world
  }
}
