// The module's target, decided once (idr-target), and the LLVM side of the
// pipeline: the machine a program is compiled for, LLVM's pipeline for it,
// and the width of its vector registers.
#ifndef IDR_TARGET_TARGET_H
#define IDR_TARGET_TARGET_H

#include "mlir/IR/BuiltinOps.h"
#include "mlir/Pass/Pass.h"

#include "llvm/ADT/StringRef.h"
#include "llvm/Target/TargetMachine.h"

#include <memory>

namespace llvm {
class Module;
class Target;
class Triple;
} // namespace llvm

namespace idr {
#define GEN_PASS_DECL_IDRTARGET
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

namespace idr::target {

// The machine a program, or the runtime prepared for every program, is
// compiled for: IEEE arithmetic with no fused operations, every function
// and datum in a section of its own, position-independent, optimized as
// far as LLVM goes. The triple, CPU and features are the module's target.
// Null when LLVM has no machine for them.
std::unique_ptr<llvm::TargetMachine> machine(const llvm::Target &target, const llvm::Triple &triple,
                                             llvm::StringRef cpu, llvm::StringRef features);

// LLVM's O3 pipeline for the machine, with MergeFunctions: identical
// functions (clones that specialization left equal) become one.
void optimize(llvm::Module &module, llvm::TargetMachine &machine);

// The width of the target's vector registers in bits, read from the
// module's `#llvm.target` (the one place the target is decided): 256 on
// x86-64 with AVX (x86-64-v3), 512 with AVX-512, else 128 (SSE2, NEON). A
// module without a target computes on 128. What idr-vectorize tiles a
// parallel dimension by, over the width of the words it computes.
unsigned vectorBits(mlir::ModuleOp module);

} // namespace idr::target

#endif // IDR_TARGET_TARGET_H
