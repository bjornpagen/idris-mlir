// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// How control leaves a region by idr.yield: to the results of the op whose
// region it ends, every one of which is a region branch (a match, a join
// point's op, a region run once, the test of sharing, a trusted library's
// IO action run for a value), so the parent says where control goes. How
// it enters their regions is each op's own; how it leaves by a jump is
// idr.jump's.

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
