// The LLVM side of the pipeline that idris-mlir-cc and idr-eval's JIT
// share: one semantics for Double at compile time and at runtime.
#pragma once

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

} // namespace idr
