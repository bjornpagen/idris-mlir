// narrowed-lanes: after idr-narrow-lanes, some loop computes integer lanes
// in 32 bits or fewer, and every wider one has a 32-bit version beside it.
export module idr.expect:narrowedLanes;

import idr.mlir;
import idr.graph;

import :report;
import :roots;

using namespace mlir;

namespace idr::expect {

// The widest integer lane `op` computes, in bits: an elementwise op on
// vectors of integers that computes (no cast, and no select, which move
// lanes and cost the same at any width); 0 when it is no such op.
static unsigned laneBits(Operation *op) {
  if (!op->hasTrait<OpTrait::Elementwise>() || isa<CastOpInterface, arith::SelectOp>(op))
    return 0;
  unsigned bits = 0;
  auto note = [&](Type type) {
    if (isa<VectorType>(type))
      bits = std::max(bits, ConstantIntRanges::getStorageBitwidth(type));
  };
  for (Type type : op->getOperandTypes())
    note(type);
  for (Type type : op->getResultTypes())
    note(type);
  return bits;
}

// The widest integer lane the loop `loop` computes, in bits; 0 when none.
static unsigned widestLane(Operation *loop) {
  unsigned bits = 0;
  loop->walk([&](Operation *op) { bits = std::max(bits, laneBits(op)); });
  return bits;
}

// After idr-narrow-lanes, in the function the argument names or anywhere,
// some loop computes integer lanes in 32 bits or fewer, and every loop
// that computes integer lanes wider than 32 bits (an elementwise op on a
// vector of such integers, other than a cast or a select, which only move
// lanes) and may run more than once is the 64-bit version beside a loop
// that computes its lanes in 32: the else region of an scf.if whose then
// region holds one.
export LogicalResult narrowedLanes(ModuleOp module, StringRef function) {
  constexpr StringRef property = "narrowed-lanes";
  SmallVector<Operation *> roots = rootsOf(module, function, property);
  if (roots.empty())
    return failure();
  bool held = true, narrow = false;
  for (Operation *root : roots)
    root->walk([&](scf::ForOp loop) {
      // The outermost loop of a nest speaks for the nest.
      if (loop->getParentOfType<scf::ForOp>())
        return;
      unsigned bits = widestLane(loop);
      if (bits == 0)
        return;
      if (bits <= 32) {
        narrow = true;
        return;
      }
      // A loop that runs at most once has no version to pay for.
      if (idr::graph::runsAtMostOnce(loop))
        return;
      // The 64-bit version stands in the else region of a version whose
      // then region holds a loop computing its lanes in 32 bits.
      bool paired = false;
      for (Operation *parent = loop->getParentOp(); parent && !paired; parent = parent->getParentOp()) {
        auto version = dyn_cast<scf::IfOp>(parent);
        if (!version || !version.getElseRegion().isAncestor(loop->getParentRegion()))
          continue;
        version.getThenRegion().walk([&](scf::ForOp other) {
          unsigned narrowed = widestLane(other);
          paired |= narrowed != 0 && narrowed <= 32;
        });
      }
      if (paired)
        return;
      fail(loop.getLoc(), property) << "a loop computes integer lanes of " << bits
                                    << " bits with no 32-bit version in " << where(loop);
      held = false;
    });
  if (!narrow) {
    fail(roots.front()->getLoc(), property) << "no loop computes integer lanes in 32 bits"
                                            << (function.empty() ? "" : " in ") << function;
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
