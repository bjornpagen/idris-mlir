// idr-prune: code that dead-code analysis proves unreachable is emptied
// before remove-dead-values sees it (OPT-PIPE-5; PINS.md:
// prune-before-remove-dead-values).
//
// remove-dead-values runs the same analyses and treats every value in a
// block they never reach as dead: it erases the arguments of such a
// function, and the values defined outside such a block that only it uses,
// but keeps the ops that use them, and then crashes on their null operands.
// So this pass, with dead-code analysis and constant propagation loaded as
// remove-dead-values loads them, empties every unreachable function body
// and match region: a match region ends in `ub.unreachable`, and a function
// body returns `ub.poison` (a body never ends in `ub.unreachable`,
// IDR-CRASH-1).
// Nothing reachable changes, so the program means what it meant.

#include "idr/Idr.h"

#include "mlir/Analysis/DataFlow/DeadCodeAnalysis.h"
#include "mlir/Analysis/DataFlow/Utils.h"
#include "mlir/Analysis/DataFlowFramework.h"
#include "mlir/Dialect/UB/IR/UBOps.h"

using namespace mlir;
using namespace mlir::dataflow;

namespace idr {
#define GEN_PASS_DEF_IDRPRUNE
#include "idr/Passes.h.inc"
} // namespace idr

namespace {

// Whether `block` is empty already: nothing but `ub.unreachable`, or a
// function body that returns only poison.
bool isEmptied(Block &block) {
  Operation *terminator = block.getTerminator();
  if (isa<ub::UnreachableOp>(terminator))
    return &block.front() == terminator;
  return isa<func::ReturnOp>(terminator) &&
         llvm::all_of(block.without_terminator(), llvm::IsaPred<ub::PoisonOp>);
}

void empty(Block &block) {
  while (!block.empty())
    block.back().erase();
  Operation *parent = block.getParentOp();
  OpBuilder b = OpBuilder::atBlockEnd(&block);
  Location loc = parent->getLoc();
  auto fn = dyn_cast<func::FuncOp>(parent);
  if (!fn) {
    ub::UnreachableOp::create(b, loc);
    return;
  }
  SmallVector<Value> results = llvm::map_to_vector(fn.getResultTypes(), [&](Type type) -> Value {
    return ub::PoisonOp::create(b, loc, type);
  });
  func::ReturnOp::create(b, loc, results);
}

struct Prune : idr::impl::IdrPruneBase<Prune> {
  void runOnOperation() override {
    DataFlowSolver solver(DataFlowConfig().setInterprocedural(true));
    loadBaselineAnalyses(solver);
    if (failed(solver.initializeAndRun(getOperation())))
      return signalPassFailure();

    // Outermost first: a block inside an unreachable one goes with it.
    SmallVector<Block *> unreachable;
    getOperation().walk<WalkOrder::PreOrder>([&](Block *block) {
      // Only a function body or a match region can end in what empty()
      // puts there; other regions are only walked into.
      if (!isa<func::FuncOp, idr::MatchOp, idr::MatchLitOp>(block->getParentOp()))
        return WalkResult::advance();
      if (block->empty() || isEmptied(*block))
        return WalkResult::skip();
      const auto *live = solver.lookupState<Executable>(solver.getProgramPointBefore(block));
      if (live && live->isLive())
        return WalkResult::advance();
      unreachable.push_back(block);
      return WalkResult::skip();
    });
    for (Block *block : unreachable)
      empty(*block);
    if (unreachable.empty())
      markAllAnalysesPreserved();
  }
};

} // namespace
