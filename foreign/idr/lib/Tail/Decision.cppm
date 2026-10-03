// idr.tail:decision: the body of a function that decides once per call
// whether to go round again.
export module idr.tail:decision;

import idr.mlir;
import idr.dialect;
import idr.graph;

import :reaches;

using namespace mlir;

namespace idr::tail {

// The body of a function that decides once per call whether to go round
// again: the match whose results it returns, the region of it that ends in
// the self tail call, and the one that reaches none.
struct Decision {
  Operation *match;
  Region *loops;
  Region *exits;
};

std::optional<Decision> decisionOf(func::FuncOp fn) {
  Operation *ret = fn.getBody().front().getTerminator();
  if (!graph::passesOnPrevious(ret) || !isTailMatch(ret->getPrevNode()))
    return std::nullopt;
  Operation *match = ret->getPrevNode();
  if (match->getNumRegions() != 2)
    return std::nullopt;
  Decision decision{match, nullptr, nullptr};
  for (Region &region : match->getRegions()) {
    if (region.empty())
      return std::nullopt;
    Operation *end = region.front().getTerminator();
    if (isa<idr::YieldOp>(end) && graph::passesOnPrevious(end) &&
        graph::isSelfCall(end->getPrevNode(), fn))
      decision.loops = &region;
    else if (!reachesTailCall(region.front(), fn))
      decision.exits = &region;
  }
  if (!decision.loops || !decision.exits)
    return std::nullopt;
  // The loop tests an integer against the one key of its case, or the
  // constructor of a value.
  if (auto lit = dyn_cast<idr::MatchLitOp>(match))
    if (!isa<IntegerType>(lit.getScrutinee().getType()) || lit.getCases().size() != 1)
      return std::nullopt;
  return decision;
}

} // namespace idr::tail
