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
// The pass reads its own function and nothing else but the declaration of
// a scrutinee's type, which no pass running beside it changes, and builds
// the loop inside the body without changing the function's type.
//
//===----------------------------------------------------------------------===//

#include "idr/Transforms/Tail.h"

#include "idr/Analysis/Tail.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"

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

namespace {

// The decision that `fn`'s body is, or none.
std::optional<Decision> decisionOf(FuncOp fn) {
  Operation *ret = fn.getBody().front().getTerminator();
  Operation *match = tailMatch(ret);
  if (!match || match->getNumRegions() != 2)
    return std::nullopt;
  Decision decision{match, nullptr, nullptr};
  for (Region &region : match->getRegions()) {
    if (region.empty())
      return std::nullopt;
    Operation *end = region.front().getTerminator();
    if (isa<YieldOp>(end) && passesOnPrevious(end) && isSelfCall(end->getPrevNode(), fn))
      decision.loops = &region;
    else if (!reachesTailCall(region.front(), fn))
      decision.exits = &region;
  }
  if (!decision.loops || !decision.exits)
    return std::nullopt;
  // The loop tests an integer against the one key of its case, or the
  // constructor of a value.
  if (auto lit = dyn_cast<MatchLitOp>(match))
    if (!isa<IntegerType>(lit.getScrutinee().getType()) || lit.getCases().size() != 1)
      return std::nullopt;
  return decision;
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
    if (fn.isExternal() || !reachesTailCall(fn.getBody().front(), fn))
      return markAllAnalysesPreserved();
    ++numLoops;
    IRRewriter rewriter(fn.getContext());
    std::optional<Decision> decision = decisionOf(fn);
    FailureOr<scf::WhileOp> loop = failure();
    if (decision)
      loop = whileDo(fn, *decision, rewriter);
    if (failed(loop)) {
      generalLoop(fn, rewriter);
      return;
    }
    // Code that the loop does not change moves out of it, and a loop that
    // counts to a bound becomes an scf.for; one that does not stays a while.
    moveLoopInvariantCode(
        loop->getLoopRegions(),
        [&](Value value, Region *) { return loop->isDefinedOutsideOfLoop(value); },
        [&](Operation *op, Region *) { return invariantCode(op); },
        [&](Operation *op, Region *) { loop->moveOutOfLoop(op); });
    rewriter.setInsertionPoint(*loop);
    if (succeeded(scf::upliftWhileToForLoop(rewriter, *loop)))
      ++numCounted;
  }
};

} // namespace
} // namespace idr::tail
