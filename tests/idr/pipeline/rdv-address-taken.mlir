// RUN: idris-mlir-opt %s --idr-prune --remove-dead-values > %t.mlir
// RUN: FileCheck %s < %t.mlir
// @f is named by a closure, so remove-dead-values keeps its parameters, but
// at the pin it still finds %y, which @g passes to the parameter @f never
// reads, dead: it erases the parameter of @g and leaves the call a null
// operand (PINS.md: remove-dead-values-address-taken). Raising and apply of
// a known closure make such calls. idr-prune passes poison there first, so
// the parameter of @g goes and the call keeps its operands.
// CHECK-LABEL: func.func private @g(
// CHECK-SAME: %[[X:[a-z0-9_]+]]: i64) -> i64
// CHECK-NEXT: %[[P:.*]] = ub.poison : i64
// CHECK-NEXT: %[[R:.*]] = call @f(%[[X]], %[[P]]) : (i64, i64) -> i64
// CHECK-NEXT: return %[[R]]
module attributes {idr.program} {
  func.func private @f(%a: i64, %b: i64) -> i64 attributes {idr.total} {
    return %a : i64
  }
  func.func private @g(%x: i64, %y: i64) -> i64 attributes {idr.total} {
    %r = func.call @f(%x, %y) : (i64, i64) -> i64
    return %r : i64
  }
  func.func private @h(%x: i64) -> !idr.fn<(i64) -> (i64)> attributes {idr.total} {
    %c = idr.closure @f(%x) : (i64) -> !idr.fn<(i64) -> (i64)>
    return %c : !idr.fn<(i64) -> (i64)>
  }
  func.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %r = func.call @g(%n, %n) : (i64, i64) -> i64
    %k = func.call @h(%n) : (i64) -> !idr.fn<(i64) -> (i64)>
    %s = idr.apply %k(%r) : !idr.fn<(i64) -> (i64)>
    %w2 = idr.io.put_int signed %s, %w1 : i64
    return %w2 : !idr.world
  }
}
