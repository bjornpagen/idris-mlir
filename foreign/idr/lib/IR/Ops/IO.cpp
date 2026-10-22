// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What the IO ops and the guards need by hand: a trusted library's IO run
// for a value runs its one region once, entered from the op and leaving to
// its results, as scf.execute_region does; and the operand a guard guards,
// its first, which GuardOpInterface gives.

#include "idr/IR/IdrDialect.h"

#include "mlir/Interfaces/ControlFlowInterfaces.h"

using namespace mlir;
using namespace idr;

void IoUnsafeRunOp::getSuccessorRegions(RegionBranchPoint point,
                                        SmallVectorImpl<RegionSuccessor> &regions) {
  if (point.isParent()) {
    regions.push_back(RegionSuccessor(&getBody()));
    return;
  }
  regions.push_back(RegionSuccessor(getOperation()));
}

Value idr::guardedOperand(Operation *guard) { return guard->getOperand(0); }
