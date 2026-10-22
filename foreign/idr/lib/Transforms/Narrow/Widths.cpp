// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a vectorized loop computes on, what it reads from outside, and how
// often it runs.

#include "idr/IR/Effects/Whole.h"
#include "idr/Transforms/Narrow.h"

#include "llvm/ADT/SetVector.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/Utils/StaticValueUtils.h"
#include "mlir/Dialect/Vector/IR/VectorOps.h"
#include "mlir/IR/AffineMap.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Matchers.h"
#include "mlir/Interfaces/CastInterfaces.h"
#include "mlir/Interfaces/ValueBoundsOpInterface.h"
#include "mlir/Transforms/RegionUtils.h"

#include "llvm/ADT/STLExtras.h"

#include <cstdint>
#include <optional>
#include <algorithm>

using namespace mlir;

namespace idr::narrow {

// A loop is vectorized when it computes on vectors, has no results (a loop
// over buffers), and holds nothing but vector ops (a mask and the
// transfers it holds included), the loops of its tiles and ops that only
// compute and hold no region. A tile the vectorization schedule could not
// vectorize keeps its linalg.generic, and a branch or a call keeps its
// scalar code, so a loop holding one is not vectorized, nor is a loop
// around a vectorized one that stores: the tile loops are the outermost
// such loops.
bool isVectorized(scf::ForOp loop) {
  if (loop->getNumResults() != 0)
    return false;
  bool vectors = false;
  WalkResult walk = loop.walk([&](Operation *op) {
    if (isa_and_nonnull<vector::VectorDialect>(op->getDialect())) {
      vectors = true;
      return WalkResult::advance();
    }
    if (isa<scf::ForOp, scf::YieldOp>(op))
      return WalkResult::advance();
    if (op->getNumRegions() != 0 || !effects::own(op).onlyComputes())
      return WalkResult::interrupt();
    return WalkResult::advance();
  });
  return vectors && !walk.wasInterrupted();
}

SetVector<Value> inputsOf(scf::ForOp loop) {
  SetVector<Value> inputs;
  inputs.insert_range(loop->getOperands());
  getUsedValuesDefinedAbove(loop->getRegions(), inputs);
  return inputs;
}

// The version tests an integer wider than 32 bits or an index, no
// constant, whose range the analysis cannot know.
bool testable(Value value) {
  Type type = value.getType();
  return (type.isIndex() || (type.isSignlessInteger() && type.getIntOrFloatBitWidth() > 32)) &&
         !matchPattern(value, m_Constant());
}

bool fits32(const ConstantIntRanges &range) {
  return range.smin().getSignificantBits() <= 32 && range.smax().getSignificantBits() <= 32;
}

// An op computes on the integers of its types when it is elementwise and
// neither a cast nor a select; on lanes of them when one is a vector. The
// widest of its types says how wide.
LaneWidth laneWidth(Operation *op) {
  if (!op->hasTrait<OpTrait::Elementwise>() || isa<CastOpInterface, arith::SelectOp>(op))
    return {0, false};
  LaneWidth width{0, false};
  for (Type type : llvm::concat<const Type>(op->getOperandTypes(), op->getResultTypes())) {
    width.bits = std::max(width.bits, ConstantIntRanges::getStorageBitwidth(type));
    width.lanes = width.lanes || isa<VectorType>(type);
  }
  return width;
}

// The greatest set: an op reached from the argument stays while each use of
// its results is the yield's operand that carries the argument round or an
// op that stays. An op nothing reads is on no path to the yield. The ops
// reached are found once each; every one starts kept, and one that does
// not feed only the set leaves it, once, after which the kept ops that
// feed it are asked again. The asking ends with the ops that leave. What
// is reached and kept is a bit per op of `root`, by its number.
Accumulations::Accumulations(Operation *root) {
  root->walk<WalkOrder::PreOrder>([&](Operation *op) {
    number.try_emplace(op, static_cast<std::uint32_t>(ops.size()));
    ops.push_back(op);
  });
  carried.resize(static_cast<unsigned>(ops.size()));
  llvm::BitVector reachedAt(static_cast<unsigned>(ops.size()));
  llvm::BitVector kept(static_cast<unsigned>(ops.size()));
  // The number of `op`, an op of `root`: every op a value of `root` meets
  // is one, but a use outside it, which no loop of it reaches.
  auto numberOf = [&](Operation *op) -> std::optional<std::uint32_t> {
    auto found = number.find(op);
    if (found == number.end())
      return std::nullopt;
    return found->second;
  };
  root->walk([&](scf::ForOp loop) {
    Operation *yield = loop.getBody()->getTerminator();
    for (auto [index, arg] : llvm::enumerate(loop.getRegionIterArgs())) {
      if (!isa<VectorType>(arg.getType()))
        continue;
      OpOperand &next = yield->getOpOperand(static_cast<unsigned>(index));
      reachedAt.reset();
      kept.reset();
      // Each op enters once, in the order reached, and is read from the
      // front: the ops of a loop are finitely many.
      footprint::Vector<std::uint32_t> reached;
      auto reach = [&](Value value) {
        for (Operation *user : value.getUsers()) {
          std::optional<std::uint32_t> at = numberOf(user);
          if (at && user->hasTrait<OpTrait::Elementwise>() && !reachedAt.test(*at)) {
            reachedAt.set(*at);
            reached.push_back(*at);
          }
        }
      };
      reach(arg);
      for (size_t at = 0; at < reached.size(); ++at)
        for (Value result : ops[reached[at]]->getResults())
          reach(result);
      kept = reachedAt;
      auto feeds = [&](std::uint32_t at) {
        Operation *op = ops[at];
        return !op->use_empty() && llvm::all_of(op->getUses(), [&](OpOperand &use) {
          std::optional<std::uint32_t> owner = numberOf(use.getOwner());
          return &use == &next || (owner && kept.test(*owner));
        });
      };
      // An op leaves once: its bit is cleared as it leaves.
      SmallVector<std::uint32_t> left;
      auto ask = [&](std::uint32_t at) {
        if (kept.test(at) && !feeds(at)) {
          kept.reset(at);
          left.push_back(at);
        }
      };
      for (std::uint32_t at : reached)
        ask(at);
      while (!left.empty())
        for (Value operand : ops[left.pop_back_val()]->getOperands())
          if (std::optional<std::uint32_t> def = numberOf(operand.getDefiningOp()))
            ask(*def);
      carried |= kept;
    }
  });
}

bool Accumulations::contains(Operation *op) const {
  auto found = number.find(op);
  return found != number.end() && carried.test(found->second);
}

// Lanes of integers wider than 32 bits are what the narrowing is for, but
// for an accumulation's.
bool computesWideLanes(scf::ForOp loop) {
  Accumulations carried(loop);
  return loop
      .walk([&](Operation *op) {
        LaneWidth width = laneWidth(op);
        return width.lanes && width.bits > 32 && !carried.contains(op) ? WalkResult::interrupt()
                                                                       : WalkResult::advance();
      })
      .wasInterrupted();
}

// A loop runs at most once when its upper bound exceeds its lower bound by
// less than a step, as for the loop of a peeled tile loop's last tile,
// whose bounds are `n - n mod step` and `n`.
bool runsAtMostOnce(scf::ForOp loop) {
  std::optional<int64_t> step = getConstantIntValue(loop.getStep());
  if (!step || *step <= 0)
    return false;
  MLIRContext *ctx = loop.getContext();
  auto span = AffineMap::get(2, 0, getAffineDimExpr(0, ctx) - getAffineDimExpr(1, ctx));
  // An upper bound is open: the span is below it.
  FailureOr<int64_t> bound = ValueBoundsConstraintSet::computeConstantBound(
      presburger::BoundType::UB,
      ValueBoundsConstraintSet::Variable(span,
                                         ValueRange{loop.getUpperBound(), loop.getLowerBound()}));
  return succeeded(bound) && *bound <= *step;
}

} // namespace idr::narrow
