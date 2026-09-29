// RUN: idris-mlir-opt %s --idr-defunctionalize > %t.mlir
// RUN: FileCheck %s < %t.mlir
// later 0 = Delay 1; later n = Delay (force (later (n - 1))): each level
// suspends a computation that captures the suspension below, so the Lazy
// type's key is on a cycle: it becomes a boxed sum, a suspension a cell,
// and forcing a match that calls the suspended function.
// CHECK: idr.data @[[F:fn\$[0-9]+]] box {
// CHECK-NOT: !idr.fn
// CHECK-NOT: idr.closure
// CHECK-LABEL: func.func private @Main.later(
// CHECK-SAME: -> !idr.box<@[[F]]>
// CHECK: idr.con @[[F]]::@Main.force(%{{.*}}) : (!idr.box<@[[F]]>) -> !idr.box<@[[F]]>
module attributes {idr.program} {
  func.func private @Main.one() -> i64 attributes {idr.total} {
    %c1 = arith.constant 1 : i64
    return %c1 : i64
  }
  func.func private @Main.force(%l: !idr.fn<() -> (i64)>) -> i64 attributes {idr.total} {
    %c1 = arith.constant 1 : i64
    %v = idr.apply %l() : !idr.fn<() -> (i64)>
    %r = arith.addi %v, %c1 : i64
    return %r : i64
  }
  func.func private @Main.later(%n: i64) -> !idr.fn<() -> (i64)> {
    %r = idr.match_lit %n : i64 -> (!idr.fn<() -> (i64)>) {
    case 0 {
      %f = idr.closure @Main.one() : () -> !idr.fn<() -> (i64)>
      idr.yield %f : !idr.fn<() -> (i64)>
    }
    default {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %g = func.call @Main.later(%m) : (i64) -> !idr.fn<() -> (i64)>
      %h = idr.closure @Main.force(%g) : (!idr.fn<() -> (i64)>) -> !idr.fn<() -> (i64)> loc("Main.idr":13:9)
      idr.yield %h : !idr.fn<() -> (i64)>
    }
    }
    return %r : !idr.fn<() -> (i64)>
  }
  func.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_char %w
    %n = arith.extui %c : i32 to i64
    %l = func.call @Main.later(%n) : (i64) -> !idr.fn<() -> (i64)>
    %s = idr.apply %l() : !idr.fn<() -> (i64)>
    %w2 = idr.io.put_int signed %s, %w1 : i64
    return %w2 : !idr.world
  }
}
