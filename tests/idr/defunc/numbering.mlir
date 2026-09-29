// RUN: idris-mlir-opt %s --idr-defunctionalize > %t.mlir
// RUN: idris-mlir-opt %s --idr-defunctionalize > %t2.mlir
// RUN: diff %t.mlir %t2.mlir
// RUN: FileCheck %s < %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=no-closures -o /dev/null
// The sums are numbered by the first appearance of their (type, labels) in
// the module, not grouped by type or ordered by name: {@Main.b} of
// i64 -> i64 first (the result of @Main.onlyB), then {@Main.zneg} of
// i1 -> i1, then {@Main.a, @Main.b} of i64 -> i64 (the argument of
// @Main.use). Two runs print the same module.
// CHECK: idr.data @fn$0 closures {
// CHECK-NEXT: idr.ctor @Main.b tag 0 ()
// CHECK-NEXT: }
// CHECK-NEXT: idr.data @fn$1 closures {
// CHECK-NEXT: idr.ctor @Main.zneg tag 0 ()
// CHECK-NEXT: }
// CHECK-NEXT: idr.data @fn$2 closures {
// CHECK-NEXT: idr.ctor @Main.a tag 0 ()
// CHECK-NEXT: idr.ctor @Main.b tag 1 ()
// CHECK-NEXT: }
// CHECK-NOT: idr.data @fn$3
// CHECK-NOT: !idr.fn
// CHECK-LABEL: func.func private @Main.onlyB() -> !idr.data<@fn$0>
// CHECK-LABEL: func.func private @Main.neg() -> !idr.data<@fn$1>
// CHECK-LABEL: func.func private @Main.use(
// CHECK-SAME: %{{.*}}: !idr.data<@fn$2>
module attributes {idr.program} {
  func.func private @Main.a(%x: i64) -> i64 attributes {idr.total} {
    %c1 = arith.constant 1 : i64
    %y = arith.addi %x, %c1 : i64
    return %y : i64
  }
  func.func private @Main.b(%x: i64) -> i64 attributes {idr.total} {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  func.func private @Main.zneg(%b: i1) -> i1 attributes {idr.total} {
    %t = arith.constant true
    %r = arith.xori %b, %t : i1
    return %r : i1
  }
  func.func private @Main.onlyB() -> !idr.fn<(i64) -> (i64)> attributes {idr.total} {
    %f = idr.closure @Main.b() : () -> !idr.fn<(i64) -> (i64)>
    return %f : !idr.fn<(i64) -> (i64)>
  }
  func.func private @Main.neg() -> !idr.fn<(i1) -> (i1)> attributes {idr.total} {
    %f = idr.closure @Main.zneg() : () -> !idr.fn<(i1) -> (i1)>
    return %f : !idr.fn<(i1) -> (i1)>
  }
  func.func private @Main.use(%f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 attributes {idr.total} {
    %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    return %y : i64
  }
  func.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_char %w
    %n = arith.extui %c : i32 to i64
    %fb = func.call @Main.onlyB() : () -> !idr.fn<(i64) -> (i64)>
    %fa = idr.closure @Main.a() : () -> !idr.fn<(i64) -> (i64)>
    %r1 = func.call @Main.use(%fa, %n) : (!idr.fn<(i64) -> (i64)>, i64) -> i64
    %r2 = func.call @Main.use(%fb, %n) : (!idr.fn<(i64) -> (i64)>, i64) -> i64
    %g = func.call @Main.neg() : () -> !idr.fn<(i1) -> (i1)>
    %e = arith.cmpi eq, %r1, %r2 : i64
    %ne = idr.apply %g(%e) : !idr.fn<(i1) -> (i1)>
    %x = arith.extui %ne : i1 to i64
    %w2 = idr.io.put_int signed %x, %w1 : i64
    return %w2 : !idr.world
  }
}
