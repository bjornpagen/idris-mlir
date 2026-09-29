// RUN: idris-mlir-opt %s --idr-specialize > %t.mlir
// RUN: FileCheck %s < %t.mlir
// A clone's parameter for a runtime leaf of a static shape is used as often
// as the product of the quantities on the way down to it: the pair is a
// parameter of quantity 1 and its first field is declared 1, so the first
// leaf is used once; its second field is declared w, so the second leaf may
// be used any number of times. A parameter the clone keeps keeps its own.
// CHECK-LABEL: func.func private @use(
// CHECK: call @[[F:first\$spec\$[0-9]+]](%{{.*}}, %{{.*}}, %{{.*}})
// CHECK: func.func private @[[F]](
// CHECK-SAME: %{{[a-z0-9_]+}}: i64 {idr.hole = {{[0-9]+}} : i64, idr.quantity = "1"}
// CHECK-SAME: %{{[a-z0-9_]+}}: i64 {idr.hole = {{[0-9]+}} : i64, idr.quantity = "w"}
// CHECK-SAME: %{{[a-z0-9_]+}}: !idr.world {idr.hole = {{[0-9]+}} : i64, idr.quantity = "1"}
module attributes {idr.program} {
  idr.data @P {
    idr.ctor @MkP tag 0 (i64, i64) {quantities = ["1", "w"]}
  }
  func.func private @first(%p: !idr.data<@P> {idr.quantity = "1"}, %w: !idr.world {idr.quantity = "1"}) -> !idr.world attributes {idr.total} {
    %w1 = idr.match %p : !idr.data<@P> -> (!idr.world) {
    case @MkP(%a: i64, %b: i64) {
      %v = idr.io.put_int signed %a, %w : i64
      idr.yield %v : !idr.world
    }
    }
    return %w1 : !idr.world
  }
  func.func @Main.main(%a: i64 {idr.quantity = "1"}, %b: i64 {idr.quantity = "w"}, %w: !idr.world {idr.quantity = "1"}) -> !idr.world {
    %r = func.call @use(%a, %b, %w) : (i64, i64, !idr.world) -> !idr.world
    return %r : !idr.world
  }
  func.func private @use(%a: i64 {idr.quantity = "1"}, %b: i64 {idr.quantity = "w"}, %w: !idr.world {idr.quantity = "1"}) -> !idr.world attributes {idr.total} {
    %p = idr.con @P::@MkP(%a, %b) : (i64, i64) -> !idr.data<@P>
    %r = func.call @first(%p, %w) : (!idr.data<@P>, !idr.world) -> !idr.world
    return %r : !idr.world
  }
}
