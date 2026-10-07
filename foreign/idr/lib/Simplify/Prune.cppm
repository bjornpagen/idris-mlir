// idr.simplify:prune: code that dead-code analysis proves unreachable is
// emptied before remove-dead-values sees it (PINS.md:
// prune-before-remove-dead-values).
//
// remove-dead-values runs the same analyses and treats every value in a
// block they never reach as dead: it erases the arguments of such a
// function, and the values defined outside such a block that only it uses,
// but keeps the ops that use them, and then crashes on their null operands.
// So idr-prune, with dead-code analysis and constant propagation loaded as
// remove-dead-values loads them, empties every unreachable function body
// and match region: a match region ends in `ub.unreachable`, and a function
// body returns `ub.poison` (returnNever).
// Nothing reachable changes, so the program means what it meant.
export module idr.simplify:prune;

import idr.mlir;
import idr.dialect;

import :returnNever;

using namespace mlir;
using namespace mlir::dataflow;

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
  if (auto fn = dyn_cast<func::FuncOp>(parent))
    idr::simplify::returnNever(b, parent->getLoc(), fn);
  else
    ub::UnreachableOp::create(b, parent->getLoc());
}

} // namespace

namespace idr::simplify {

// What `prune` changed: the blocks it emptied.
export struct Pruned {
  uint64_t emptied = 0;
};

// Empties the unreachable code of `module`. Fails when the analyses fail.
export FailureOr<Pruned> prune(ModuleOp module) {
  Pruned pruned;
  DataFlowSolver solver(DataFlowConfig().setInterprocedural(true));
  loadBaselineAnalyses(solver);
  if (failed(solver.initializeAndRun(module)))
    return failure();

  // Outermost first: a block inside an unreachable one goes with it.
  SmallVector<Block *> unreachable;
  module.walk<WalkOrder::PreOrder>([&](Block *block) {
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
  pruned.emptied = unreachable.size();
  return pruned;
}

} // namespace idr::simplify
