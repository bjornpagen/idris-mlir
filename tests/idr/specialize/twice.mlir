// RUN: idris-mlir-opt %s --idr-specialize > %t.mlir
// RUN: FileCheck %s < %t.mlir
// One pair passed as both arguments: the clone takes its leaves once per
// parameter, and the pair, which nothing else reads, goes with the call it
// fed, once.
// CHECK-LABEL: func.func private @use(
// CHECK-NOT: idr.con
// CHECK: call @[[S:sum\$spec\$[0-9]+]](
// CHECK: func.func private @[[S]](
module attributes {idr.program} {
  idr.data @P {
    idr.ctor @MkP (i64, i64)
  }
  func.func private @sum(%p: !idr.data<@P>, %q: !idr.data<@P>) -> i64 {
    %a = idr.field %p[@MkP, 0] : !idr.data<@P> -> i64
    %b = idr.field %q[@MkP, 1] : !idr.data<@P> -> i64
    %r = arith.addi %a, %b : i64
    return %r : i64
  }
  func.func private @use(%a: i64, %b: i64) -> i64 {
    %p = idr.con @P::@MkP(%a, %b) : (i64, i64) -> !idr.data<@P>
    %r = func.call @sum(%p, %p) : (!idr.data<@P>, !idr.data<@P>) -> i64
    return %r : i64
  }
  func.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_char %w
    %b = arith.extui %c : i32 to i64
    %r = func.call @use(%b, %b) : (i64, i64) -> i64
    %w2 = idr.io.put_int signed %r, %w1 : i64
    return %w2 : !idr.world
  }
}
