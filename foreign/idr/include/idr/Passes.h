// What the optimization passes (lib/Passes/) offer the rest of the compiler.
#pragma once

#include "mlir/IR/Diagnostics.h"

#include "llvm/ADT/SmallVector.h"

#include <string>

namespace idr {

// The passes of one round of idr-simplify, as textual pipelines,
// in order.
llvm::SmallVector<std::string> simplifyRound(unsigned inlineIterations, unsigned cloneLimit);

// Whether a diagnostic is idr-check-profile's rejection of the program: a
// user error (exit status 3), not an internal one.
bool isProfileRejection(const mlir::Diagnostic &diag);

} // namespace idr
