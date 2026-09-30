// RUN: idris-mlir-opt %s --llvm-target-to-target-features --idr-lower | FileCheck %s
// @main asks the runtime's entry for the processor features the module's
// target enables, as bits of IDRIS_RT_CPU_FEATURES: x86-64-v3 is bits 0 to
// 15 (v2's seven and v3's nine), and no AVX-512.
// CHECK-LABEL: func.func @main() -> i32
// CHECK: %[[CPU:.*]] = arith.constant 65535 : i64
// CHECK: llvm.call @idris_rt_start(%{{.*}}, %[[CPU]])
module attributes {idr.program, llvm.target = #llvm.target<triple = "x86_64-unknown-linux-musl", chip = "x86-64-v3">} {
  func.func @Prog.main() -> i64 {
    %c = arith.constant 7 : i64
    return %c : i64
  }
}
