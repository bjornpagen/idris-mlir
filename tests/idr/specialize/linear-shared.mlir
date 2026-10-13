// RUN: idris-mlir-opt %s --idr-specialize > %t.mlir
// RUN: FileCheck %s < %t.mlir
// A call on a static shape moves the shape's leaves into the clone's call.
// Here the pair is read twice, so it outlives each call: a clone taking its
// linear field would use it a second time next to the pair. The pair stays
// a runtime argument, and the module still verifies after the pass.
// CHECK-LABEL: idr.func private @use(
// CHECK: call @first(%{{.*}}, %{{.*}}) : (!P, !idr.world)
// CHECK: call @first(%{{.*}}, %{{.*}}) : (!P, !idr.world)
// CHECK-NOT: .spec
module attributes {idr.program} {
  idr.data @P {
    idr.ctor @MkP (!idr.lin<i64>, i64)
  }
  idr.func private @first(%p: !idr.data<@P>, %w: !idr.world) -> !idr.world attributes {total} {
    %w1 = idr.match %p : !idr.data<@P> -> (!idr.world) {
    case @MkP(%a: i64, %b: i64) {
      %v = idr.io.put_int signed %a, %w : i64
      idr.yield %v : !idr.world
    }
    }
    return %w1 : !idr.world
  }
  idr.func private @use(%a: !idr.lin<i64>, %b: i64, %w: !idr.world) -> !idr.world attributes {total} {
    %p = idr.con @P::@MkP(%a, %b) : (!idr.lin<i64>, i64) -> !idr.data<@P>
    %r = idr.call @first(%p, %w) : (!idr.data<@P>, !idr.world) -> !idr.world
    %s = idr.call @first(%p, %r) : (!idr.data<@P>, !idr.world) -> !idr.world
    return %s : !idr.world
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %b = arith.extui %c : i32 to i64
    %a = idr.lin.enter %b : !idr.lin<i64>
    %r = idr.call @use(%a, %b, %w1) : (!idr.lin<i64>, i64, !idr.world) -> !idr.world
    return %r : !idr.world
  }
}
