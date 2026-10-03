// idr.ops:matchsuccessors: a match as a RegionBranchOpInterface, as
// scf.index_switch: control enters exactly one region, which returns to
// the match.
export module idr.ops:matchsuccessors;

import idr.mlir;

using namespace mlir;

export namespace idr::ops {

// From a region, back to the match; from the match, into every region.
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

} // namespace idr::ops
