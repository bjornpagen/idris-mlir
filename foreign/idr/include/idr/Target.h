// The LLVM side of OPT-PIPE-1 that idris-mlir-cc and idr-eval's JIT share
// (LOW-TARGET-1): one semantics for Double at compile time and at runtime.
#pragma once

#include "llvm/IR/Module.h"
#include "llvm/Target/TargetMachine.h"
#include "llvm/Target/TargetOptions.h"

namespace idr {

// No fast-math and no FP contraction anywhere (docs/plan.md section 5.7):
// `+` and `*` are IEEE operations, never fused.
llvm::TargetOptions targetOptions();

// LLVM's O3 pipeline for the machine, with MergeFunctions: identical
// functions (clones that specialization left equal) become one.
void optimize(llvm::Module &module, llvm::TargetMachine &machine);

} // namespace idr
