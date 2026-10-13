// narrowed-lanes: after idr-narrow-lanes, some loop computes integer lanes
// in 32 bits or fewer, and every wider one has a 32-bit version beside it.

#include "idr/Transforms/Expect.h"

#include "idr/Transforms/Narrow.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/Interfaces/CastInterfaces.h"
#include "mlir/Interfaces/InferIntRangeInterface.h"

#include <algorithm>

using namespace mlir;

namespace idr::expect {

namespace {

// The widest integer lane `op` computes, in bits: an elementwise op on
// vectors of integers that computes (no cast, and no select, which move
// lanes and cost the same at any width); 0 when it is no such op.
unsigned laneBits(Operation *op) {
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
unsigned widestLane(Operation *loop) {
  unsigned bits = 0;
  loop->walk([&](Operation *op) { bits = std::max(bits, laneBits(op)); });
  return bits;
}

} // namespace

// After idr-narrow-lanes, in the function the argument names or anywhere,
// some loop computes integer lanes in 32 bits or fewer, and every loop
// that computes integer lanes wider than 32 bits (an elementwise op on a
// vector of such integers, other than a cast or a select, which only move
// lanes) and may run more than once is the 64-bit version beside a loop
// that computes its lanes in 32: the else region of an scf.if whose then
// region holds one.
LogicalResult narrowedLanes(ModuleOp module, AnalysisManager &analyses, StringRef function) {
  constexpr StringRef property = "narrowed-lanes";
  SmallVector<Operation *> roots =
      rootsOf(module, analyses.getAnalysis<SymbolTable>(), function, property);
  if (roots.empty())
    return failure();
  bool held = true, someNarrow = false;
  for (Operation *root : roots)
    root->walk([&](scf::ForOp loop) {
      // The outermost loop of a nest speaks for the nest.
      if (loop->getParentOfType<scf::ForOp>())
        return;
      unsigned bits = widestLane(loop);
      if (bits == 0)
        return;
      if (bits <= 32) {
        someNarrow = true;
        return;
      }
      // A loop that runs at most once has no version to pay for, which is
      // how idr-narrow-lanes decides it, by the one test.
      if (idr::narrow::runsAtMostOnce(loop))
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
  if (!someNarrow) {
    fail(roots.front()->getLoc(), property) << "no loop computes integer lanes in 32 bits"
                                            << (function.empty() ? "" : " in ") << function;
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
