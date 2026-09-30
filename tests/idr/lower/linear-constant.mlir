// RUN: idris-mlir-opt %s --idr-lower | FileCheck %s
// A constant with a linear field is laid out as the constant with the
// value itself there: linearity has no runtime form, in static data too.
// CHECK-LABEL: func.func private @action() -> (i8, i64, i64)
// CHECK-DAG: llvm.mlir.constant(1 : i8) : i8
// CHECK-DAG: llvm.mlir.constant(2 : i64) : i64
// CHECK-DAG: llvm.mlir.constant(3 : i64) : i64
// CHECK: return %{{.*}}, %{{.*}}, %{{.*}} : i8, i64, i64
module attributes {idr.program} {
  idr.data @Step {
    idr.ctor @Done (i64)
    idr.ctor @Bind (i64, i64)
  }
  idr.data @IO {
    idr.ctor @MkIO (!idr.lin<!idr.data<@Step>>)
  }
  func.func private @action() -> !idr.data<@IO> {
    %c = idr.constant #idr.con<@IO::@MkIO, [#idr.con<@Step::@Bind, [2, 3]>]> : !idr.data<@IO>
    return %c : !idr.data<@IO>
  }
  func.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
