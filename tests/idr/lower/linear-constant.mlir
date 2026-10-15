// RUN: idris-mlir-opt %s --idr-lower | FileCheck %s
// A constant with a linear field is laid out as the constant with the
// value itself there: linearity has no runtime form, in static data too.
// CHECK-LABEL: func.func private @action() -> (i8, i64, i64)
// CHECK-DAG: llvm.mlir.constant(1 : i8) : i8
// CHECK-DAG: llvm.mlir.constant(2 : i64) : i64
// CHECK-DAG: llvm.mlir.constant(3 : i64) : i64
// CHECK: return %{{.*}}, %{{.*}}, %{{.*}} : i8, i64, i64
!Step = !idr.data<"Step", plain [@Done(i64), @Bind(i64, i64)]>
!IO = !idr.data<"IO", plain [@MkIO(!idr.lin<!Step>)]>
module {
  idr.func private @action() -> !IO {
    %c = idr.constant #idr.con<@MkIO, [#idr.con<@Bind, [2, 3]>]> : !IO
    return %c : !IO
  }
  idr.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
