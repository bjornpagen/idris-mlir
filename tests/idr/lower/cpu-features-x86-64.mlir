// RUN: idris-mlir-opt %s --llvm-target-to-target-features --idr-lower --idr-entry -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=entry,calls=@main:@idris_rt_start -o /dev/null
// @main asks the runtime's entry for the processor features the module's
// target enables, as bits of IDRIS_RT_CPU_FEATURES: with the x86-64
// entry's list (runtime/cpu_x86_64.h), x86-64-v3 is bits 0 to 15 (v2's
// seven and v3's nine), and no AVX-512: the runtime's own word.
// An x86-64 test: it needs that entry.
module attributes {llvm.target = #llvm.target<triple = "x86_64-unknown-linux-gnu", chip = "x86-64-v3">} {
  idr.program @"cpu-features-x86-64" root(@Prog.main) stage(owned) {
    idr.func @Prog.main() -> i64 {
      %c = arith.constant 7 : i64
      return %c : i64
    }
  }
}
