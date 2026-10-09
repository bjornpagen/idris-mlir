// RUN: idris-mlir-opt %s --idr-lower --idr-meter > %t.mlir
// RUN: FileCheck %s < %t.mlir
// RUN: FileCheck %s --check-prefix=DECL < %t.mlir
// RUN: idris-mlir-opt %s --idr-lower | FileCheck %s --check-prefix=PROGRAM --implicit-check-not=idris_rt_eval_tick
// idr-meter counts a tick of the evaluator's meter where code may go on
// for ever: on entry to every function, so a call that recurses without
// end runs out, total or not, and before each llvm.sideeffect, the effect
// a loop that may not end keeps, so such a loop runs out too. Compile-time
// evaluation runs it after idr-lower, which has no mode and counts no tick
// itself.
// DECL: llvm.func @idris_rt_eval_tick()
// PROGRAM: llvm.call_intrinsic "llvm.sideeffect"()
// CHECK-LABEL: func.func private @spin(
// CHECK-NEXT: llvm.call @idris_rt_eval_tick() : () -> ()
// CHECK: scf.while
// CHECK: } do {
// CHECK: llvm.call @idris_rt_eval_tick() : () -> ()
// CHECK-NEXT: llvm.call_intrinsic "llvm.sideeffect"()
// CHECK: return
// CHECK-LABEL: func.func private @sum(
// CHECK-NEXT: llvm.call @idris_rt_eval_tick() : () -> ()
// CHECK-NEXT: arith.addi
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
  func.func private @sum(%a: i64, %b: i64) -> i64 attributes {idr.total} {
    %s = arith.addi %a, %b : i64
    return %s : i64
  }
  func.func @Prog.main() -> i64 {
    %one = arith.constant 1 : i64
    func.call @spin(%one) : (i64) -> ()
    %s = func.call @sum(%one, %one) : (i64, i64) -> i64
    return %s : i64
  }
}
