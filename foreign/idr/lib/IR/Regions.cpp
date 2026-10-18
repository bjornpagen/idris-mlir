// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// How control leaves the regions of a match: the yield that ends one goes
// on to the match's results. How it enters them is the match's own
// (Idr_MatchOpBase, IdrMatchOps.td).

#include "idr/IR/IdrDialect.h"

#include "mlir/Interfaces/ControlFlowInterfaces.h"

using namespace mlir;
using namespace idr;

void YieldOp::getSuccessorRegions(ArrayRef<Attribute>, SmallVectorImpl<RegionSuccessor> &regions) {
  cast<RegionBranchOpInterface>((*this)->getParentOp())
      .getSuccessorRegions(
          RegionBranchPoint(cast<RegionBranchTerminatorOpInterface>(getOperation())), regions);
}

// A match's yield is the match's results.
MutableOperandRange YieldOp::getMutableSuccessorOperands(RegionSuccessor) {
  return MutableOperandRange(*this);
}
