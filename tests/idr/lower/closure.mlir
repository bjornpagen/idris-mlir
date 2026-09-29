// RUN: idris-mlir-opt %s --idr-lower=jit=true | FileCheck %s
// Only idr-eval's lowering (jit) meets closures: the program's have all
// become sums. A closure's cell holds its label, the address of its code
// and the captures; applying it calls the code with the closure first. The
// code loads the captures and calls the function with them before the
// arguments.
// CHECK-LABEL: func.func private @adder(
// CHECK: %[[C:.*]] = llvm.call @{{.*}}(%{{.*}}) : (i64) -> !llvm.ptr
// CHECK: %[[F:.*]] = constant @[[CODEFN:__idr_code_[0-9]+]] : (!llvm.ptr, i64) -> i64
// CHECK: %[[FP:.*]] = builtin.unrealized_conversion_cast %[[F]] : (!llvm.ptr, i64) -> i64 to !llvm.ptr
// CHECK: %[[CODE:.*]] = llvm.getelementptr %[[C]][8] : (!llvm.ptr) -> !llvm.ptr, i8
// CHECK: llvm.store %[[FP]], %[[CODE]] : !llvm.ptr, !llvm.ptr
// CHECK-LABEL: func.func private @run(
// CHECK: %[[CP:.*]] = llvm.getelementptr %arg0[8] : (!llvm.ptr) -> !llvm.ptr, i8
// CHECK: %[[CODE2:.*]] = llvm.load %[[CP]] : !llvm.ptr -> !llvm.ptr
// CHECK: %[[FN:.*]] = builtin.unrealized_conversion_cast %[[CODE2]] : !llvm.ptr to (!llvm.ptr, i64) -> i64
// CHECK: call_indirect %[[FN]](%arg0, %arg1) : (!llvm.ptr, i64) -> i64
// CHECK: func.func private @[[CODEFN]](
// CHECK-SAME: %[[ENV:.*]]: !llvm.ptr, %[[X:.*]]: i64) -> i64
// CHECK: %[[K:.*]] = llvm.getelementptr %[[ENV]][16] : (!llvm.ptr) -> !llvm.ptr, i8
// CHECK: %[[KV:.*]] = llvm.load %[[K]] : !llvm.ptr -> i64
// CHECK: call @add(%[[KV]], %[[X]]) : (i64, i64) -> i64
module attributes {idr.program} {
  func.func private @add(%k: i64, %x: i64) -> i64 {
    %r = arith.addi %k, %x : i64
    return %r : i64
  }
  func.func private @adder(%k: i64) -> !idr.fn<(i64) -> (i64)> {
    %c = idr.closure @add(%k) : (i64) -> !idr.fn<(i64) -> (i64)>
    return %c : !idr.fn<(i64) -> (i64)>
  }
  func.func private @run(%f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 {
    %r = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    return %r : i64
  }
  func.func @Prog.main() -> i64 {
    %one = arith.constant 1 : i64
    %f = func.call @adder(%one) : (i64) -> !idr.fn<(i64) -> (i64)>
    %r = func.call @run(%f, %one) : (!idr.fn<(i64) -> (i64)>, i64) -> i64
    return %r : i64
  }
}
