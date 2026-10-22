// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// How control leaves a region by idr.yield: to the results of the op whose
// region it ends, a match or a join point's op. How it enters their regions
// is each op's own (OpsMatch.cpp, Control/Joins.cpp); how it leaves by a
// jump is idr.jump's.

#include "idr/IR/IdrDialect.h"

#include "mlir/Interfaces/ControlFlowInterfaces.h"

using namespace mlir;
using namespace idr;

void YieldOp::getSuccessorRegions(ArrayRef<Attribute>, SmallVectorImpl<RegionSuccessor> &regions) {
  cast<RegionBranchOpInterface>((*this)->getParentOp())
      .getSuccessorRegions(
          RegionBranchPoint(cast<RegionBranchTerminatorOpInterface>(getOperation())), regions);
}

// A yield's operands are its parent's results.
MutableOperandRange YieldOp::getMutableSuccessorOperands(RegionSuccessor) {
  return MutableOperandRange(*this);
}
