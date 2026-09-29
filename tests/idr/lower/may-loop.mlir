// RUN: idris-mlir-opt %s --idr-lower --canonicalize | FileCheck %s
// idr.may_loop, which idr-tail-loops puts in the loops of functions that
// are not total, becomes an effect in the loop's body that no MLIR pass
// removes and LLVM keeps in place: llvm.sideeffect, which emits no
// instruction. So an unused loop that may not terminate stays.
// CHECK-LABEL: func.func private @spin(
// CHECK: scf.while
// CHECK: } do {
// CHECK: llvm.call_intrinsic "llvm.sideeffect"()
// CHECK: scf.yield
module attributes {idr.program} {
  func.func private @spin(%n: i64) {
    %r = scf.while (%x = %n) : (i64) -> i64 {
      %zero = arith.constant 0 : i64
      %more = arith.cmpi ne, %x, %zero : i64
      scf.condition(%more) %x : i64
    } do {
    ^bb0(%x: i64):
      idr.may_loop
      scf.yield %x : i64
    }
    return
  }
  func.func @Prog.main() -> i64 {
    %one = arith.constant 1 : i64
    func.call @spin(%one) : (i64) -> ()
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
