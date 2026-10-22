// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What idr.data.match and idr.lit.match share, one template each,
// instantiated per match: the region a known key takes, the edges
// upstream's control-flow interfaces read off them, the bounds of their
// regions, the rules ODS cannot state, and a match remade with fewer
// cases. A key is a tag of idr.data.match or a literal of idr.lit.match,
// two different things, so each is written over the op.
//
// A region ends by yielding the match's results, by jumping to an enclosing
// join point, which the match lets through, or by never ending. That is
// each terminator's own rule: a yield names its parents, a jump checks what
// it crosses, and a terminator that never ends has no successor.
#ifndef IDR_LIB_IR_CONTROL_MATCHFAMILY_H
#define IDR_LIB_IR_CONTROL_MATCHFAMILY_H

#include "idr/IR/Control/Stated.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Lifetimes.h"

#include "mlir/IR/PatternMatch.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"

#include <type_traits>

namespace idr::control {

// The two members of the match family, each with its key.
template <typename Match>
concept MatchFamily = requires(Match op) {
  op.getCases();
  op.getDefaultRegion();
  op.getCaseRegions();
};

// An empty default region and one per case, the default first.
inline void addRegions(mlir::OperationState &state, size_t cases) {
  for (size_t region = 0; region <= cases; ++region)
    state.addRegion();
}

// The region of `op` its key `key` takes: its case, else the default. An
// empty default never runs: the key is then one the match has no region
// for, which nothing reaches.
template <MatchFamily Match, typename Key>
mlir::Region *takenRegion(Match op, Key key) {
  auto cases = op.getCases();
  const auto *it = llvm::find(cases, key);
  if (it != cases.end())
    return &op.getCaseRegions()[static_cast<unsigned>(it - cases.begin())];
  mlir::Region &fallback = op.getDefaultRegion();
  return fallback.empty() ? nullptr : &fallback;
}

// Every region that runs, entered from the match; the match's results,
// from a yield; from a jump to an enclosing join point, what that point's
// op says, since the match lets the jump through.
template <MatchFamily Match>
void successorsOf(Match op, mlir::RegionBranchPoint point,
                  llvm::SmallVectorImpl<mlir::RegionSuccessor> &successors) {
  if (point.isParent()) {
    for (mlir::Region &region : op->getRegions())
      if (!region.empty())
        successors.emplace_back(&region);
    return;
  }
  mlir::RegionBranchTerminatorOpInterface terminator = point.getTerminatorPredecessorOrNull();
  if (mlir::terminatorPropagatesThrough(terminator, op)) {
    mlir::appendPropagatedTerminatorSuccessors(terminator, op, successors);
    return;
  }
  successors.push_back(mlir::RegionSuccessor(op.getOperation()));
}

// The region taken when it is known, else every region that runs.
template <MatchFamily Match>
void entrySuccessorsOf(Match op, mlir::Region *taken,
                       llvm::SmallVectorImpl<mlir::RegionSuccessor> &successors) {
  if (taken)
    successors.emplace_back(taken);
  else
    successorsOf(op, mlir::RegionBranchPoint::parent(), successors);
}

// At most once each region that runs, and none but the taken one when it
// is known.
template <MatchFamily Match>
void boundsOf(Match op, mlir::Region *taken, llvm::SmallVectorImpl<mlir::InvocationBounds> &bounds) {
  for (mlir::Region &region : op->getRegions())
    bounds.emplace_back(/*lb=*/0,
                        /*ub=*/!region.empty() && (!taken || taken == &region) ? 1 : 0);
}

// One key per case region, each once. ODS ties no key to a case region, so
// the two lists are held to one length here. And the match states one
// lifetime per scoped value it makes.
template <MatchFamily Match>
mlir::LogicalResult verifyKeys(Match op) {
  if (op.getCases().size() != op.getCaseRegions().size())
    return op.emitOpError("expects one key per case region");
  llvm::SmallDenseSet<std::decay_t<decltype(*op.getCases().begin())>> seen;
  for (auto key : op.getCases())
    if (!seen.insert(key).second)
      return op.emitOpError("has two cases for one key");
  return lifetimes::verifyOuters(op, 0);
}

// A match like `op` holding the cases `kept` alone, made by `make` from
// their keys, with `fallback` as its default: the regions moved in, `op`
// replaced. Its results are `op`'s, and each region kept binds what it
// bound, so it states the lifetimes `op` states.
template <MatchFamily Match, typename Make>
Match keepCasesOf(Match op, mlir::RewriterBase &rewriter, llvm::ArrayRef<unsigned> kept,
                  mlir::Region *fallback, Make &&make) {
  rewriter.setInsertionPoint(op);
  Match fresh = make();
  rewriter.modifyOpInPlace(fresh, [&] { fresh.getOutersMutable().assign(op.getOuters()); });
  for (auto [index, into] : llvm::zip_equal(kept, fresh.getCaseRegions()))
    rewriter.inlineRegionBefore(op.getCaseRegions()[index], into, into.end());
  if (fallback) {
    mlir::Region &into = fresh.getDefaultRegion();
    rewriter.inlineRegionBefore(*fallback, into, into.end());
  }
  rewriter.replaceOp(op, fresh->getResults());
  return fresh;
}

// A region gives the match's results at their own types: what a case
// learned of a value leaves it only through a cast its scope checks.
inline mlir::LogicalResult verifyYields(mlir::Operation *op) {
  for (mlir::Region &region : op->getRegions())
    if (!region.empty())
      if (auto yield = llvm::dyn_cast<YieldOp>(region.front().getTerminator());
          yield && mlir::TypeRange(yield.getResults()) != op->getResultTypes())
        return op->emitOpError("region #")
               << region.getRegionNumber() << " yields " << yield.getResults().getTypes()
               << " for results of types " << op->getResultTypes();
  return mlir::success();
}

} // namespace idr::control

#endif // IDR_LIB_IR_CONTROL_MATCHFAMILY_H
