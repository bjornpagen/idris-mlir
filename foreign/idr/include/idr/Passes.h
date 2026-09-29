// What the optimization passes (lib/Passes/) offer the rest of the compiler.
#pragma once

#include "llvm/ADT/SmallVector.h"

#include <string>

namespace idr {

// The passes of one round of idr-simplify, as textual pipelines,
// in order.
llvm::SmallVector<std::string> simplifyRound(unsigned inlineIterations, unsigned cloneLimit);

} // namespace idr
