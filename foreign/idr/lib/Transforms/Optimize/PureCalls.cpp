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
//     first dominates it, is the first's results. The first dominates when
//     it comes earlier in the same block, or in a block that encloses the
//     second's region.
// A callee of the function's own component is not final, so its calls stay
// as they are.
//
// A linear value is used once on every path. A call that takes one is that
// use, so it stays even when nothing reads it; a call that gives one gives a
// fresh value, so two such calls stay two values.

#include "idr/Transforms/Optimize.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/OperationSupport.h"
#include "mlir/Pass/Pass.h"
#include "llvm/ADT/DenseMapInfo.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/ScopedHashTable.h"
#include "llvm/ADT/SmallVector.h"

#include <cstddef>

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

struct PureCalls : PassWrapper<PureCalls, OperationPass<idr::FuncOp>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(PureCalls)

  PureCalls() = default;
  // A copy for another pipeline: its statistics are its own.
  PureCalls(const PureCalls &other) : PassWrapper(other) {}

  StringRef getArgument() const override { return "idr-pure-calls"; }
  StringRef getDescription() const override {
    return "Erase each unread call of a pure final callee, and merge each identical one into "
           "the call that dominates it";
  }

  Statistic numErased{this, "erased", "Calls of a pure callee whose results nothing read, erased"};
  Statistic numMerged{this, "merged",
                      "Calls of a pure callee given the results of an identical call before them"};

  void runOnOperation() override {
    idr::FuncOp fn = getOperation();
    auto set = getCachedParentAnalysis<idr::optimize::ReadySet>();
    if (!set) {
      fn.emitError("internal error: idr-pure-calls runs inside idr-optimize, whose ready set "
                   "holds the summaries of its program");
      return signalPassFailure();
    }
    const idr::optimize::ReadySet &ready = set->get();
    auto pure = [&](idr::CallOp call) {
      const idr::optimize::Summary *summary = ready.summaryOf(call.getCalleeAttr().getAttr());
      return summary && summary->effects == idr::Effect::none;
    };

    Known known;
    unsigned merged = merge(fn.getBody(), known, pure);

    // Users before what they use, so that a call whose one reader was a
    // pure call erased here goes too.
    SmallVector<idr::CallOp> calls;
    fn.getBody().walk<WalkOrder::PreOrder>([&](idr::CallOp call) { calls.push_back(call); });
    unsigned erased = 0;
    for (idr::CallOp call : llvm::reverse(calls)) {
      if (!call->use_empty() || !pure(call) ||
          llvm::any_of(call.getArgs().getTypes(), idr::isLinear))
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
  // dominates it; how many. Each block opens a scope, so what a block
  // records is seen by the rest of it and by the regions its ops hold, and
  // by nothing after it.
  template <typename Pure>
  unsigned merge(Region &region, Known &known, Pure &pure) {
    unsigned merged = 0;
    for (Block &block : region) {
      Known::ScopeTy scope(known);
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
          merged += merge(nested, known, pure);
      }
    }
    return merged;
  }
};

} // namespace

std::unique_ptr<Pass> idr::optimize::createPureCallsPass() { return std::make_unique<PureCalls>(); }
