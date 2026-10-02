// The LLVM side of the pipeline that idris-mlir-cc and idr-eval's JIT
// share: one semantics for Double at compile time and at runtime.
#pragma once

#include "mlir/IR/BuiltinOps.h"

#include "llvm/IR/Module.h"
#include "llvm/Target/TargetMachine.h"
#include "llvm/Target/TargetOptions.h"

namespace idr {

// No fast-math and no FP contraction anywhere:
// `+` and `*` are IEEE operations, never fused.
llvm::TargetOptions targetOptions();

// LLVM's O3 pipeline for the machine, with MergeFunctions: identical
// functions (clones that specialization left equal) become one.
void optimize(llvm::Module &module, llvm::TargetMachine &machine);

// The width of the target's vector registers in bits, read from the
// module's `#llvm.target` (the one place the target is decided): 256 on
// x86-64 with AVX (x86-64-v3), 512 with AVX-512, else 128 (SSE2, NEON). A
// module without a target computes on 128. What idr-vectorize tiles a
// parallel dimension by, over the width of the words it computes.
unsigned vectorBits(mlir::ModuleOp module);

} // namespace idr
