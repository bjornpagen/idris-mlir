// RUN: idris-mlir-opt %s --canonicalize --idr-lower | FileCheck %s
// canonicalize turns a match that only chooses between two values into
// arith.select, also of an idr type; that select chooses each component.
// CHECK-LABEL: func.func private @pick(
// CHECK-SAME: %[[C:.*]]: i1
// CHECK-DAG: arith.select %[[C]], %{{.*}}, %{{.*}} : i8
// CHECK-DAG: arith.select %[[C]], %{{.*}}, %{{.*}} : i64
!T = !idr.data<"T", plain [@A(i64), @B()]>
module {
  idr.func private @pick(%c: i1, %x: !T, %y: !T) -> !T {
    %r = arith.select %c, %x, %y : !T
    return %r : !T
  }
  idr.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
