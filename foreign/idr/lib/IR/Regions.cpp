// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// How control enters and leaves every region op of the dialect: a match
// branches into its regions, as a region branch op, and the yield that ends
// a region goes on to the match's results.

#include "idr/IR/IdrDialect.h"

#include "mlir/Interfaces/ControlFlowInterfaces.h"

using namespace mlir;
using namespace idr;

namespace {

// A match as a RegionBranchOpInterface, as scf.index_switch: control enters
// exactly one region, which returns to the match. From a region, back to
// the match; from the match, into every region.
void matchSuccessors(Operation *op, RegionBranchPoint point,
                     SmallVectorImpl<RegionSuccessor> &successors) {
  if (!point.isParent()) {
    successors.push_back(RegionSuccessor(op));
    return;
  }
  for (Region &region : op->getRegions())
    successors.emplace_back(&region);
}

// The region `taken`, when the match is known to take it; else every one.
void matchEntrySuccessors(Operation *op, Region *taken,
                          SmallVectorImpl<RegionSuccessor> &successors) {
  if (taken)
    successors.emplace_back(taken);
  else
    matchSuccessors(op, RegionBranchPoint::parent(), successors);
}

// At most once each region, and none but `taken` when it is known.
void matchInvocationBounds(Operation *op, Region *taken,
                           SmallVectorImpl<InvocationBounds> &bounds) {
  for (Region &region : op->getRegions())
    bounds.emplace_back(/*lb=*/0, /*ub=*/!taken || taken == &region ? 1 : 0);
}

} // namespace

//===----------------------------------------------------------------------===//
// The matches
//===----------------------------------------------------------------------===//

void MatchOp::getSuccessorRegions(RegionBranchPoint point,
                                  SmallVectorImpl<RegionSuccessor> &successors) {
  matchSuccessors(*this, point, successors);
}

void MatchOp::getEntrySuccessorRegions(ArrayRef<Attribute> operands,
                                       SmallVectorImpl<RegionSuccessor> &successors) {
  matchEntrySuccessors(*this, getTakenRegion(operands.front()), successors);
}

void MatchOp::getRegionInvocationBounds(ArrayRef<Attribute> operands,
                                        SmallVectorImpl<InvocationBounds> &bounds) {
  matchInvocationBounds(*this, getTakenRegion(operands.front()), bounds);
}

ValueRange MatchOp::getSuccessorInputs(RegionSuccessor successor) {
  return successor.isOperation() ? ValueRange(getResults()) : ValueRange();
}

void MatchLitOp::getSuccessorRegions(RegionBranchPoint point,
                                     SmallVectorImpl<RegionSuccessor> &successors) {
  matchSuccessors(*this, point, successors);
}

void MatchLitOp::getEntrySuccessorRegions(ArrayRef<Attribute> operands,
                                          SmallVectorImpl<RegionSuccessor> &successors) {
  matchEntrySuccessors(*this, getTakenRegion(operands.front()), successors);
}

void MatchLitOp::getRegionInvocationBounds(ArrayRef<Attribute> operands,
                                           SmallVectorImpl<InvocationBounds> &bounds) {
  matchInvocationBounds(*this, getTakenRegion(operands.front()), bounds);
}

ValueRange MatchLitOp::getSuccessorInputs(RegionSuccessor successor) {
  return successor.isOperation() ? ValueRange(getResults()) : ValueRange();
}

//===----------------------------------------------------------------------===//
// The yield
//===----------------------------------------------------------------------===//

void YieldOp::getSuccessorRegions(ArrayRef<Attribute>, SmallVectorImpl<RegionSuccessor> &regions) {
  cast<RegionBranchOpInterface>((*this)->getParentOp())
      .getSuccessorRegions(
          RegionBranchPoint(cast<RegionBranchTerminatorOpInterface>(getOperation())), regions);
}

// A match's yield is the match's results.
MutableOperandRange YieldOp::getMutableSuccessorOperands(RegionSuccessor) {
  return MutableOperandRange(*this);
}
