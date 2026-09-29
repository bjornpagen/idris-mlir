// RUN: idris-mlir-opt %s --canonicalize --idr-lower | FileCheck %s
// canonicalize turns a match that only chooses between two values into
// arith.select, also of an idr type; that select chooses each component.
// CHECK-LABEL: func.func private @pick(
// CHECK-SAME: %[[C:.*]]: i1
// CHECK-DAG: arith.select %[[C]], %{{.*}}, %{{.*}} : i8
// CHECK-DAG: arith.select %[[C]], %{{.*}}, %{{.*}} : i64
module attributes {idr.program} {
  idr.data @T {
    idr.ctor @A tag 0 (i64)
    idr.ctor @B tag 1 ()
  }
  func.func private @pick(%c: i1, %x: !idr.data<@T>, %y: !idr.data<@T>) -> !idr.data<@T> {
    %r = arith.select %c, %x, %y : !idr.data<@T>
    return %r : !idr.data<@T>
  }
  func.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
