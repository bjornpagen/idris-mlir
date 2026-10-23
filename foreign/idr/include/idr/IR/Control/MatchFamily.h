// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What idr.data.match and idr.lit.match share, one template each,
// instantiated per match: the region a known key takes, the edges
// upstream's control-flow interfaces read off them, the bounds of their
// regions, the rules ODS cannot state, and a match remade with fewer
// cases. A key is a tag of idr.data.match or a literal of idr.lit.match,
// two different things, so each is written over the op, and two keys are
// one exactly when they are equal: a tag is its constructor's number, and
// a literal is its value's one form, since each carrier admits one literal
// per value (LiteralTypeInterface::isLiteral), so identity is every
// carrier's equality on keys.
//
// A region ends by yielding the match's results, by jumping to an enclosing
// join point, which the match lets through, or by never ending. That is
// each terminator's own rule: a yield names its parents, a jump checks what
// it crosses, and a terminator that never ends has no successor.
#ifndef IDR_IR_CONTROL_MATCHFAMILY_H
#define IDR_IR_CONTROL_MATCHFAMILY_H

#include "idr/IR/Control/Stated.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Lifetimes.h"
#include "idr/Support/Footprint.h"

#include "mlir/IR/PatternMatch.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/ADT/STLExtras.h"

#include <cstdint>

namespace idr::control {

// The two members of the match family, each with its keys.
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

// The region of `op` its key `key` takes: the case of the key equal to it,
// else the default. An empty default never runs: the key is then one the
// match has no region for, which nothing reaches.
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

// A key as the set of a match's keys holds it. A tag is widened to 64 bits,
// so that no tag, before its match's verifier bounds it by the family, is
// one of the two values a hashed set of 32-bit integers reserves. A literal
// is held as itself: each carrier admits one literal per value (a string's
// is its one untyped string attribute, a big's is keyed by its integer at
// its fewest bits, a Double's is never a NaN, which equals nothing, nor
// negative zero, which equals zero), so two literals are one value exactly
// when they are one attribute.
inline std::int64_t heldKey(std::int32_t tag) { return tag; }
inline mlir::Attribute heldKey(mlir::Attribute literal) { return literal; }

// One key per case region, each once. ODS ties no key to a case region, so
// the two lists are held to one length here. A literal match's keys are
// known literals of its carrier before they get here, each its value's one
// form, so a key met twice is one the set already holds, and the keys are
// hashed rather than compared pairwise. And the match states one lifetime
// per scoped value it makes.
template <MatchFamily Match>
mlir::LogicalResult verifyKeys(Match op) {
  auto cases = op.getCases();
  if (cases.size() != op.getCaseRegions().size())
    return op.emitOpError("expects one key per case region");
  footprint::DenseSet<decltype(heldKey(*cases.begin()))> seen;
  for (const auto &key : cases)
    if (!seen.insert(heldKey(key)).second)
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
// Before the specializer a yielded value whose hold fits its result's
// crosses at the result's (crossedAs), as static data or a fresh value's
// claim the frontend gives where the match's result claims nothing.
inline mlir::LogicalResult verifyYields(mlir::Operation *op) {
  for (mlir::Region &region : op->getRegions())
    if (!region.empty())
      if (auto yield = llvm::dyn_cast<YieldOp>(region.front().getTerminator());
          yield && !llvm::equal(yield.getResults().getTypes(), op->getResultTypes(),
                                [&](mlir::Type given, mlir::Type asked) {
                                  return crossedAs(op, given, asked) == asked;
                                }))
        return op->emitOpError("region #")
               << region.getRegionNumber() << " yields " << yield.getResults().getTypes()
               << " for results of types " << op->getResultTypes();
  return mlir::success();
}

} // namespace idr::control

#endif // IDR_IR_CONTROL_MATCHFAMILY_H
