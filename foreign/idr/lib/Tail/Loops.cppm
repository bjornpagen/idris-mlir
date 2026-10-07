// idr.tail:loops: self tail calls become loops.
//
// A self tail call is a `func.call` of the enclosing function whose results
// are returned unchanged: it is the last op before the function's
// `func.return`, or before the `idr.yield` of a match region whose match is
// itself in tail position, and that terminator passes on exactly its results.
//
// Most such functions decide once per call whether to go round again: their
// body ends in a match whose results it returns, one region of which ends in
// the self tail call and the other reaches none. That function becomes the
// loop MLIR expects, in while-do form:
//   - the before region is the body up to the decision, and ends in
//     `scf.condition(continue)` over the arguments that change;
//   - the after region is the region that calls, its call's arguments
//     yielded as the next ones;
//   - the region that exits follows the loop, on the loop's results.
// Arguments the call passes unchanged are not carried at all, and code that
// depends on nothing the loop changes runs once, before it. A loop that
// counts up to a bound is then exactly what upstream's uplift recognizes,
// and becomes an scf.for with a trip count.
//
// Any other function with a self tail call becomes one `scf.while` over its
// arguments A whose before region is the old body. Every tail position of
// the body then yields a payload (continue : i1, A, R):
//   - a self tail call yields (true, its arguments, poison R);
//   - any other result yields (false, poison A, the results R);
// the matches on the way yield the payload of their regions, and the region
// ends in `scf.condition(continue) A, R`. The after region passes A back to
// the before region, and the function returns the R of the loop's results.
//
// A function without `idr.total` may not terminate, so its loop gets
// `idr.may_loop`: a loop without effects whose results are unused would
// otherwise be trivially dead upstream. Nothing here adds a
// progress guarantee.
export module idr.tail:loops;

import idr.mlir;
import idr.dialect;

import :decision;
import :loop;
import :reaches;
import :whileDo;

using namespace mlir;

namespace {

// Whether `op`, in a loop, may run once before it instead: it has no
// effect, cannot fail, and holds no reference, so no count changes
// whichever iteration's copy it is.
bool invariantCode(Operation *op) {
  return isMemoryEffectFree(op) && isSpeculatable(op) &&
         llvm::none_of(op->getResults(), [](Value result) { return idr::isOwned(result.getType()); });
}

} // namespace

namespace idr::tail {

// What `makeLoops` made: the functions that became loops, and the loops
// that became counted ones.
export struct Loops {
  uint64_t loops = 0;
  uint64_t counted = 0;
};

// Makes the self tail calls of every function of `module` loops. Fails
// when the uplift of a counted loop fails.
export FailureOr<Loops> makeLoops(ModuleOp module) {
  Loops made;
  OpBuilder b(module.getContext());
  SmallVector<scf::WhileOp> loops;
  for (auto fn : module.getOps<func::FuncOp>()) {
    if (fn.isExternal() || !reachesTailCall(fn.getBody().front(), fn))
      continue;
    ++made.loops;
    if (std::optional<Decision> decision = decisionOf(fn)) {
      FailureOr<scf::WhileOp> loop = WhileDo(fn, *decision, b).build();
      if (succeeded(loop)) {
        loops.push_back(*loop);
        continue;
      }
    }
    Loop{fn, fn.getArgumentTypes(), fn.getResultTypes(), b}.build();
  }
  // Code that the loop does not change moves out of it, and a loop that
  // counts to a bound becomes an scf.for.
  for (scf::WhileOp loop : loops)
    moveLoopInvariantCode(
        loop.getLoopRegions(),
        [&](Value value, Region *) { return loop.isDefinedOutsideOfLoop(value); },
        [&](Operation *op, Region *) { return invariantCode(op); },
        [&](Operation *op, Region *) { loop.moveOutOfLoop(op); });
  RewritePatternSet uplift(module.getContext());
  scf::populateUpliftWhileToForPatterns(uplift);
  FrozenRewritePatternSet frozen(std::move(uplift));
  for (scf::WhileOp loop : loops) {
    bool erased = false;
    if (failed(applyOpPatternsGreedily({loop.getOperation()}, frozen,
                                       GreedyRewriteConfig().enableFolding(false).setStrictness(
                                           GreedyRewriteStrictness::ExistingOps),
                                       /*changed=*/nullptr, &erased)))
      return failure();
    if (erased)
      ++made.counted;
  }
  return made;
}

} // namespace idr::tail
