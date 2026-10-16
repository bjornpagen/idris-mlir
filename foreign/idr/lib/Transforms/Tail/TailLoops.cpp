// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
//===- TailLoops.cpp - idr-tail-loops -------------------------------------===//
//
// Self tail calls become loops, one function at a time.
//
// A self tail call is an idr.call of the enclosing function whose results
// are returned unchanged: it is the last op before the function's
// idr.return, or before the idr.yield of a match region whose match is
// itself in tail position, and that terminator passes on exactly its
// results.
//
// Most such functions decide once per call whether to go round again: their
// body ends in a match whose results it returns, one region of which ends in
// the self tail call and the other reaches none. That function becomes the
// loop MLIR expects, in while-do form (whileDo). Any other function with a
// self tail call becomes one scf.while over its arguments with a payload at
// every tail position (generalLoop).
//
// A function that is not total may not terminate, so its loop gets
// idr.may_loop: a loop without effects whose results are unused would
// otherwise be trivially dead upstream. Nothing here adds a progress
// guarantee.
//
// The pass reads its own function and nothing else: a scrutinee's type
// carries its constructors. It builds the loop inside the body without
// changing the function's type.
//
//===----------------------------------------------------------------------===//

#include "idr/Transforms/Tail.h"

#include "idr/Analysis/Tail.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"
#include "idr/Support/Actions.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/SCF/Transforms/Transforms.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Transforms/LoopInvariantCodeMotionUtils.h"

namespace idr {
#define GEN_PASS_DEF_IDRTAILLOOPS
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::tail {

void forTails(Block &block, function_ref<void(Block &)> f) {
  if (Operation *match = tailMatch(block.getTerminator())) {
    for (Region &region : match->getRegions())
      if (!region.empty())
        forTails(region.front(), f);
    return;
  }
  f(block);
}

bool reachesTailCall(Block &block, FuncOp fn) {
  Operation *terminator = block.getTerminator();
  if (!passesOnPrevious(terminator))
    return false;
  Operation *prev = terminator->getPrevNode();
  if (isSelfCall(prev, fn))
    return true;
  if (!isTailMatch(prev))
    return false;
  return llvm::any_of(prev->getRegions(), [&](Region &region) {
    return !region.empty() && reachesTailCall(region.front(), fn);
  });
}

FailureOr<StringAttr> copyName(FuncOp fn, StringRef kind, SymbolTable &symbols) {
  auto name = StringAttr::get(fn.getContext(), contentName(fn.getSymName(), kind, ""));
  if (!symbols.lookup(name))
    return name;
  fn.emitError() << "internal error: the name " << name.getValue() << " of the " << kind << " copy of @"
                 << fn.getSymName() << " is taken";
  return failure();
}

namespace {

// idr-tail-loops makes one function's self tail calls a loop; the unit is
// the function.
struct TailLoopAction : support::TaggedAction<TailLoopAction> {
  using TaggedAction::TaggedAction;
  static constexpr llvm::StringLiteral tag = "idr-tail-loops-loop";
};

// idr-tail-loops moves the invariant code of one while-do loop before it;
// the unit is the loop. One action for the whole loop: skipping one op of
// it would let the hoisting move that op's users above it.
struct TailHoistAction : support::TaggedAction<TailHoistAction> {
  using TaggedAction::TaggedAction;
  static constexpr llvm::StringLiteral tag = "idr-tail-loops-hoist";
};

// idr-tail-loops makes one while-do loop an scf.for; the unit is the loop.
struct TailUpliftAction : support::TaggedAction<TailUpliftAction> {
  using TaggedAction::TaggedAction;
  static constexpr llvm::StringLiteral tag = "idr-tail-loops-uplift";
};

// The decision that `fn`'s body is, or none: a match of two regions, one
// that ends in the self tail call and one that reaches none.
std::optional<Decision> decisionOf(FuncOp fn) {
  Operation *ret = fn.getBody().front().getTerminator();
  Operation *match = tailMatch(ret);
  if (!match || match->getNumRegions() != 2 ||
      llvm::any_of(match->getRegions(), [](Region &region) { return region.empty(); }))
    return std::nullopt;
  auto loops = [&](Region &region) {
    Operation *end = region.front().getTerminator();
    return isa<YieldOp>(end) && passesOnPrevious(end) && isSelfCall(end->getPrevNode(), fn);
  };
  auto exits = [&](Region &region) { return !loops(region) && !reachesTailCall(region.front(), fn); };
  MutableArrayRef<Region> regions = match->getRegions();
  auto looping = llvm::find_if(regions, loops);
  auto exiting = llvm::find_if(regions, exits);
  if (looping == regions.end() || exiting == regions.end())
    return std::nullopt;
  // The loop tests an integer against the one key of its case, or the
  // constructor of a value.
  if (auto lit = dyn_cast<MatchLitOp>(match))
    if (!isa<IntegerType>(lit.getScrutinee().getType()) || lit.getCases().size() != 1)
      return std::nullopt;
  return Decision{*match, *looping, *exiting};
}

// Whether `op`, in a loop, may run once before it instead: it has no
// effect, cannot fail, and holds no reference, so no count changes
// whichever iteration's copy it is.
bool invariantCode(Operation *op) {
  return isMemoryEffectFree(op) && isSpeculatable(op) &&
         llvm::none_of(op->getResults(), [](Value result) { return isOwned(result.getType()); });
}

struct TailLoops : impl::IdrTailLoopsBase<TailLoops> {
  void runOnOperation() override {
    FuncOp fn = getOperation();
    if (!reachesTailCall(fn.getBody().front(), fn))
      return markAllAnalysesPreserved();
    IRRewriter rewriter(fn.getContext());
    // The while-do loop when the body is a decision; failure once the
    // general loop is made instead.
    FailureOr<scf::WhileOp> loop = failure();
    if (!support::perform<TailLoopAction>(fn, [&] {
          std::optional<Decision> decision = decisionOf(fn);
          if (decision)
            loop = whileDo(fn, *decision, rewriter);
          if (failed(loop))
            generalLoop(fn, rewriter);
        }))
      return markAllAnalysesPreserved();
    ++numLoops;
    if (failed(loop))
      return;
    // Code that the loop does not change moves out of it, and a loop that
    // counts to a bound becomes an scf.for; one that does not stays a while.
    (void)support::perform<TailHoistAction>(*loop, [&] {
      moveLoopInvariantCode(
          loop->getLoopRegions(),
          [&](Value value, Region *) { return loop->isDefinedOutsideOfLoop(value); },
          [&](Operation *op, Region *) { return invariantCode(op); },
          [&](Operation *op, Region *) { loop->moveOutOfLoop(op); });
    });
    rewriter.setInsertionPoint(*loop);
    (void)support::perform<TailUpliftAction>(*loop, [&] {
      if (succeeded(scf::upliftWhileToForLoop(rewriter, *loop)))
        ++numCounted;
    });
  }
};

} // namespace
} // namespace idr::tail
