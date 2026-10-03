// idr.driver:nativeruns: whether the prepared runtime's native half runs on
// the program's CPU.
module;
// The target entry's list of processor features, an X-macro.
#include "cpu_features.h"

export module idr.driver:nativeruns;

import idr.mlir;

import :isprepared;
import :marks;
import :moduleflagstring;

export namespace idr::driver {

// Whether the prepared runtime's native half runs wherever the program does:
// the program's CPU has every feature of the CPU that half was compiled for
// that the processor test at the program's entry can name
// (IDRIS_RT_CPU_FEATURES), so the test covers both. The runtime is prepared
// for the default CPU, so this holds for every program but one compiled for
// a smaller CPU, which compiles the runtime's bodies itself.
bool nativeRuns(const llvm::Module &runtime, const llvm::Target &target, const llvm::Triple &triple,
                const llvm::TargetMachine &machine) {
  if (!isPrepared(runtime))
    return false;
  std::unique_ptr<llvm::MCSubtargetInfo> prepared(target.createMCSubtargetInfo(
      triple, moduleFlagString(runtime, preparedCpuFlag),
      moduleFlagString(runtime, preparedFeaturesFlag)));
  const llvm::MCSubtargetInfo &program = machine.getMCSubtargetInfo();
#define IDR_FEATURE(bit, test, name)                                                             \
  if (prepared->checkFeatures("+" name) && !program.checkFeatures("+" name))                     \
    return false;
  IDRIS_RT_CPU_FEATURES(IDR_FEATURE)
#undef IDR_FEATURE
  return true;
}

} // namespace idr::driver
