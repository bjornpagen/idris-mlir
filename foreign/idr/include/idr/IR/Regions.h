// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// How often a region runs for each run of the op that holds it: as
// upstream's region branch interface says, and any number of times for any
// other op with regions, whose regions no interface bounds. The verifier's
// count of uses, the lifetimes and the derivation of rows all ask it here.
#ifndef IDR_IR_REGIONS_H
#define IDR_IR_REGIONS_H

#include "mlir/IR/Operation.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"

#include <cstdint>

namespace idr {

// Whether a region may run more than once for each run of what holds it.
enum class Runs : std::uint8_t { Once, Repeatedly };

// How often region `index` of `op` runs for each run of `op`.
inline Runs regionRuns(mlir::Operation *op, unsigned index) {
  auto branch = llvm::dyn_cast<mlir::RegionBranchOpInterface>(op);
  return branch && !branch.isRepetitiveRegion(index) ? Runs::Once : Runs::Repeatedly;
}

} // namespace idr

#endif // IDR_IR_REGIONS_H
