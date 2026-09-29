// PIN(llvm-force-enable-stats): included before anything else in every
// translation unit of idr_dialect and the tools (CMakeLists.txt), so that
// llvm::Statistic, and with it every pass statistic, is the counting kind in
// every build type, as it is in the MLIR library.
#pragma once

#include "llvm/Config/llvm-config.h"

#undef LLVM_FORCE_ENABLE_STATS
#define LLVM_FORCE_ENABLE_STATS 1
