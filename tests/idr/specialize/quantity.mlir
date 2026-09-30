// RUN: idris-mlir-opt %s --idr-specialize > %t.mlir
// RUN: FileCheck %s < %t.mlir
// A clone's parameter for a runtime leaf of a static shape has the leaf's
// type, so a leaf that fills a linear field stays linear: the pair's first
// field is declared used once, its second any number of times, and the
// clone of @first takes one !idr.lin<i64> and one i64. A parameter the
// clone keeps, the world, keeps its type too.
// CHECK-LABEL: func.func private @use(
// CHECK: call @[[F:first\$spec\$[0-9]+]](%{{.*}}, %{{.*}}, %{{.*}}) : (!idr.lin<i64>, i64, !idr.world) -> !idr.world
// CHECK: func.func private @[[F]](%{{[a-z0-9_]+}}: !idr.lin<i64> {{.*}}, %{{[a-z0-9_]+}}: i64 {{.*}}, %{{[a-z0-9_]+}}: !idr.world
module attributes {idr.program} {
  idr.data @P {
    idr.ctor @MkP (!idr.lin<i64>, i64)
  }
  func.func private @first(%p: !idr.data<@P>, %w: !idr.world) -> !idr.world attributes {idr.total} {
    %w1 = idr.match %p : !idr.data<@P> -> (!idr.world) {
    case @MkP(%a: !idr.lin<i64>, %b: i64) {
      %x = idr.lin.use %a : !idr.lin<i64>
      %v = idr.io.put_int signed %x, %w : i64
      idr.yield %v : !idr.world
    }
    }
    return %w1 : !idr.world
  }
  func.func private @use(%a: !idr.lin<i64>, %b: i64, %w: !idr.world) -> !idr.world attributes {idr.total} {
    %p = idr.con @P::@MkP(%a, %b) : (!idr.lin<i64>, i64) -> !idr.data<@P>
    %r = func.call @first(%p, %w) : (!idr.data<@P>, !idr.world) -> !idr.world
    return %r : !idr.world
  }
  func.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_char %w
    %b = arith.extui %c : i32 to i64
    %a = idr.lin.enter %b : !idr.lin<i64>
    %r = func.call @use(%a, %b, %w1) : (!idr.lin<i64>, i64, !idr.world) -> !idr.world
    return %r : !idr.world
  }
}
