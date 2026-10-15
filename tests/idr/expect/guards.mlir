// RUN: idris-mlir-opt %s --idr-expect=holds=no-guards=@proved -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=no-guards=@kept -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// A function keeps no guard when every condition its partial primitives
// need is proven where it runs: a division by a nonzero constant needs
// none (@proved). Each guard left is one error (@kept).
// CHECK: error: expected no-guards: idr.check.nonzero is left in @kept
// CHECK-NOT: error:
module {
  idr.func private @proved(%x: i64) -> i64 {
    %two = arith.constant 2 : i64
    %r = idr.div signed %x, %two : i64
    return %r : i64
  }
  idr.func private @kept(%x: i64, %y: i64) -> i64 {
    %g = idr.check.nonzero %y, "division by zero" : i64
    %r = idr.div signed %x, %g : i64
    return %r : i64
  }
}
