// RUN: idris-mlir-opt %s --idr-lower | FileCheck %s
// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s --check-prefix=FOLD
// An Int written as a byte: the program crashes unless it is 0 to 255 (a
// negative Int is a large unsigned one), then the low byte is stored. A
// constant byte folds, and needs no check.
// CHECK-LABEL: func.func private @byte(
// CHECK-SAME: %[[X:[^:]*]]: i64)
// CHECK: %[[OUT:.*]] = arith.cmpi ugt, %[[X]], %{{.*}} : i64
// CHECK: scf.if %[[OUT]] {
// CHECK: llvm.call @idris_rt_crash(
// CHECK: }
// CHECK: %[[B:.*]] = arith.trunci %[[X]] : i64 to i8
// CHECK: return %[[B]]
// FOLD-LABEL: func.func private @constant(
// FOLD-NOT: idr.to_byte
// FOLD: %[[C:.*]] = arith.constant -56 : i8
// FOLD: return %[[C]]
module attributes {idr.program, idr.stage = "owned"} {
  func.func @root(%w: !idr.world) -> !idr.world {
    %in, %w1 = idr.io.get_byte %w
    %x = arith.extui %in : i32 to i64
    %b = func.call @byte(%x) : (i64) -> i8
    %c = func.call @constant() : () -> i8
    return %w1 : !idr.world
  }
  func.func private @byte(%x: i64) -> i8 {
    %b = idr.to_byte %x
    return %b : i8
  }
  func.func private @constant() -> i8 {
    %x = arith.constant 200 : i64
    %b = idr.to_byte %x
    return %b : i8
  }
}
