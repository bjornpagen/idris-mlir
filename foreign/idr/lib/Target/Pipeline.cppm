// idr.target:pipeline: LLVM's options and pipeline for the target, the same
// for executables and for idr-eval's JIT.
export module idr.target:pipeline;

import idr.mlir;

export namespace idr::target {

// No fast-math and no FP contraction anywhere:
// `+` and `*` are IEEE operations, never fused.
llvm::TargetOptions targetOptions();

// LLVM's O3 pipeline for the machine, with MergeFunctions: identical
// functions (clones that specialization left equal) become one.
void optimize(llvm::Module &module, llvm::TargetMachine &machine);

} // namespace idr::target
