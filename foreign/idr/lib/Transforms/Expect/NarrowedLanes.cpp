// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// narrowed-lanes: after idr-narrow-lanes, some loop computes integer lanes
// in 32 bits or fewer, and every wider one has a 32-bit version beside it.
// A reduction's accumulator is no such lane: a sum is as wide as the
// program made it, and narrowing it could change what it adds up to.

#include "idr/Transforms/Expect.h"

#include "idr/Transforms/Narrow.h"

#include "mlir/Dialect/SCF/IR/SCF.h"

#include <algorithm>

using namespace mlir;

namespace idr::expect {

namespace {

// The widest integer lane the loop `loop` computes, in bits, outside the
// accumulations idr-narrow-lanes leaves wide, by its own rules: what an op
// computes on is the pass's one answer (integerWidth), an op on no lanes
// counting none; 0 when none.
unsigned widestLane(Operation *loop) {
  unsigned bits = 0;
  for (Operation *op : narrow::outsideAccumulations(loop))
    if (auto w = narrow::integerWidth(op); w && w->spread == narrow::Spread::Lanes)
      bits = std::max(bits, w->bits);
  return bits;
}

} // namespace

// After idr-narrow-lanes, in the function the argument names or anywhere,
// some loop computes integer lanes in 32 bits or fewer, and every loop
// that computes integer lanes wider than 32 bits (an elementwise op on a
// vector of such integers, other than a cast or a select, which only move
// lanes, or an accumulation) and may run more than once is
// the 64-bit version beside a loop that computes its lanes in 32: the else
// region of an scf.if whose then region holds one.
LogicalResult narrowedLanes(const Request<Roots> &request) {
  SmallVector<Operation *> roots = request.argument.roots(request.module);
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
      fail(loop.getLoc(), request.property) << "a loop computes integer lanes of " << bits
                                            << " bits with no 32-bit version in " << where(loop);
      held = false;
    });
  if (!someNarrow) {
    fail(roots.front()->getLoc(), request.property)
        << "no loop computes integer lanes in 32 bits" << request.argument.in();
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
