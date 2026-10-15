// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-pure-calls: the step of idr-optimize's inner pipeline that does for
// idr.call what canonicalize and CSE do for an op whose effects they read.
// A call declares every effect to upstream's interfaces, since what it may
// do is its callee's and only the callee says; inside idr-optimize the
// ready set holds the summary of every final callee, found by name. A call
// of a final callee whose summary says it does nothing but compute (no io,
// no crash, no divergence) is pure:
//   - when nothing reads its results it goes;
//   - a second call with the same callee and the same operands, where the
//     first dominates it, is the first's results: the first comes earlier
//     in the same block, in a block that dominates the second's, or in one
//     that encloses the second's region, as DominanceInfo says.
// A callee of the function's own component is not final, so its calls stay
// as they are.
//
// The verifier's one rule for a value of quantity one is that it is used at
// most once on every path, and counting releases one that goes unused. So a
// pure call nothing reads goes even when it takes a linear operand: the
// operand loses its one use and is released like any other value left
// unused. Two dominating calls never take one linear value, which would be
// two uses on one path; a call that gives one gives a fresh value, so two
// such calls stay two values.

#include "idr/Transforms/Optimize.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Dominance.h"
#include "mlir/IR/OperationSupport.h"
#include "mlir/Pass/Pass.h"
#include "llvm/ADT/DenseMapInfo.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/ScopedHashTable.h"
#include "llvm/ADT/SmallVector.h"

#include <cstddef>

namespace idr {
#define GEN_PASS_DEF_IDRPURECALLS
#include "idr/Transforms/InnerPasses.h.inc"
} // namespace idr

using namespace mlir;

namespace {

// Two calls are one key when they are the same op but for location: the
// same callee, operands and attributes, as upstream's CSE compares ops.
struct CallKey : llvm::DenseMapInfo<Operation *> {
  static unsigned getHashValue(const Operation *call) {
    llvm::hash_code hash = OperationEquivalence::computeHash(
        const_cast<Operation *>(call), OperationEquivalence::directHashValue,
        OperationEquivalence::ignoreHashValue, OperationEquivalence::IgnoreLocations);
    return static_cast<unsigned>(static_cast<size_t>(hash));
  }
  static bool isEqual(const Operation *lhs, const Operation *rhs) {
    if (lhs == rhs)
      return true;
    return OperationEquivalence::isEquivalentTo(const_cast<Operation *>(lhs),
                                                const_cast<Operation *>(rhs),
                                                OperationEquivalence::IgnoreLocations);
  }
};

// The pure calls met so far whose results the op being visited may take:
// those of its block before it and of every block that encloses it.
using Known = llvm::ScopedHashTable<Operation *, Operation *, CallKey>;

struct PureCalls : idr::impl::IdrPureCallsBase<PureCalls> {
  PureCalls(const idr::optimize::ReadySet &set, Pass::Statistic &numErased,
            Pass::Statistic &numMerged)
      : set(set), numErased(numErased), numMerged(numMerged) {}

  void runOnOperation() override {
    idr::FuncOp fn = getOperation();
    auto pure = [&](idr::CallOp call) {
      const idr::optimize::Summary *summary = set.summaryOf(call.getCalleeAttr().getAttr());
      return summary && summary->effects == idr::Effect::none;
    };

    Known known;
    DominanceInfo &dominance = getAnalysis<DominanceInfo>();
    unsigned merged = merge(fn.getBody(), known, pure, dominance);

    // Users before what they use, so that a call whose one reader was a
    // pure call erased here goes too.
    SmallVector<idr::CallOp> calls;
    fn.getBody().walk<WalkOrder::PreOrder>([&](idr::CallOp call) { calls.push_back(call); });
    unsigned erased = 0;
    for (idr::CallOp call : llvm::reverse(calls)) {
      if (!call->use_empty() || !pure(call))
        continue;
      call.erase();
      ++erased;
    }

    numMerged += merged;
    numErased += erased;
    if (merged == 0 && erased == 0)
      markAllAnalysesPreserved();
  }

  // Gives each pure call in `region` the results of an identical one that
  // dominates it; how many. As upstream's CSE does, a block opens a scope
  // and the walk goes down the region's dominator tree, so what a block
  // records is seen by the rest of it, by the blocks it dominates and by
  // the regions its ops hold, and by nothing else. A block no path reaches
  // is in no tree, and keeps its calls.
  template <typename Pure>
  unsigned merge(Region &region, Known &known, Pure &pure, DominanceInfo &dominance) {
    if (region.empty())
      return 0;
    // A region of one block has no dominator tree.
    if (region.hasOneBlock()) {
      Known::ScopeTy scope(known);
      return mergeBlock(region.front(), known, pure, dominance);
    }
    unsigned merged = 0;
    auto visit = [&](auto &self, DominanceInfoNode *node) -> void {
      Known::ScopeTy scope(known);
      merged += mergeBlock(*node->getBlock(), known, pure, dominance);
      for (DominanceInfoNode *dominated : *node)
        self(self, dominated);
    };
    visit(visit, dominance.getRootNode(&region));
    return merged;
  }

  template <typename Pure>
  unsigned mergeBlock(Block &block, Known &known, Pure &pure, DominanceInfo &dominance) {
    unsigned merged = 0;
    for (Operation &op : llvm::make_early_inc_range(block)) {
      auto call = dyn_cast<idr::CallOp>(op);
      if (call && pure(call) && llvm::none_of(call.getResultTypes(), idr::isLinear)) {
        if (Operation *first = known.lookup(&op)) {
          op.replaceAllUsesWith(first->getResults());
          op.erase();
          ++merged;
        } else {
          known.insert(&op, &op);
        }
        continue;
      }
      for (Region &nested : op.getRegions())
        merged += merge(nested, known, pure, dominance);
    }
    return merged;
  }

  const idr::optimize::ReadySet &set;
  Pass::Statistic &numErased;
  Pass::Statistic &numMerged;
};

} // namespace

std::unique_ptr<Pass> idr::optimize::createPureCalls(const ReadySet &set, Pass::Statistic &erased,
                                                     Pass::Statistic &merged) {
  return std::make_unique<PureCalls>(set, erased, merged);
}


