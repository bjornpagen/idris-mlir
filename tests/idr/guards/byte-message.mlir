// RUN: idris-mlir-opt %s --idr-lower | FileCheck %s
// The guard of an Int written as a byte crashes unless the Int is 0 to 255:
// a negative one is a large unsigned one, so one comparison above 255
// tests both ends. Its message is its cause at its location, the one the
// partial primitive had: the program ends with the same text.
// CHECK-DAG: llvm.mlir.constant("idris-mlir: a byte outside 0 to 255 at Prog.idr:6:1\0A")
// CHECK-LABEL: func.func private @byte(
// CHECK-SAME: %[[X:[^:]*]]: i64)
// CHECK: %[[MAX:.*]] = arith.constant 255 : i64
// CHECK: %[[OUT:.*]] = arith.cmpi ugt, %[[X]], %[[MAX]] : i64
// CHECK: scf.if %[[OUT]] {
// CHECK: llvm.call @idris_rt_crash(
// CHECK: return %[[X]] : i64
module attributes {idr.program} {
  func.func private @byte(%x: i64) -> i64 {
    %y = idr.check.byte %x, "a byte outside 0 to 255" loc("Prog.idr":6:1)
    return %y : i64
  }
  func.func @Prog.main() -> i64 {
    %c = arith.constant 7 : i64
    %b = func.call @byte(%c) : (i64) -> i64
    return %b : i64
  }
}
