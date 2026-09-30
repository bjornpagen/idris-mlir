// idr-prune: code that dead-code analysis proves unreachable is emptied
// before remove-dead-values sees it (PINS.md:
// prune-before-remove-dead-values).
//
// remove-dead-values runs the same analyses and treats every value in a
// block they never reach as dead: it erases the arguments of such a
// function, and the values defined outside such a block that only it uses,
// but keeps the ops that use them, and then crashes on their null operands.
// So this pass, with dead-code analysis and constant propagation loaded as
// remove-dead-values loads them, empties every unreachable function body
// and match region: a match region ends in `ub.unreachable`, and a function
// body returns `ub.poison` (a body never ends in `ub.unreachable`:
// PINS.md: inline-unreachable).
// Nothing reachable changes, so the program means what it meant.
//
// remove-dead-values also leaves alone the parameters of a function that a
// closure names, since not every use of it is a call, but still treats a
// value passed to one that the function never reads as dead: it erases that
// value, a parameter of the caller or the op that made it, and the call
// keeps a null operand (PINS.md: remove-dead-values-address-taken). Raising
// and apply of a known closure make such calls. So a
// call of such a function passes `ub.poison` for each parameter it never
// reads, which nothing reads either.

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

// The functions some symbol use other than a call's callee names: a closure,
// a closure constant.
llvm::DenseSet<StringAttr> addressTaken(ModuleOp module) {
  llvm::DenseSet<StringAttr> taken;
  if (std::optional<SymbolTable::UseRange> uses = SymbolTable::getSymbolUses(&module.getBodyRegion()))
    for (const SymbolTable::SymbolUse &use : *uses)
      if (!isa<func::CallOp>(use.getUser()))
        taken.insert(use.getSymbolRef().getRootReference());
  return taken;
}

// Passes poison for every parameter of an address-taken function that it
// never reads. Returns the number of operands it replaced.
unsigned guardUnreadParameters(ModuleOp module) {
  llvm::DenseSet<StringAttr> taken = addressTaken(module);
  SymbolTable symbols(module);
  unsigned changed = 0;
  module.walk([&](func::CallOp call) {
    if (!taken.contains(call.getCalleeAttr().getAttr()))
      return;
    auto callee = symbols.lookup<func::FuncOp>(call.getCalleeAttr().getAttr());
    if (!callee || callee.isExternal() || callee.getNumArguments() != call.getNumOperands())
      return;
    for (BlockArgument param : callee.getArguments()) {
      Value operand = call.getOperand(param.getArgNumber());
      if (!param.use_empty() || idr::isWorld(param.getType()) || idr::isErased(param.getType()) ||
          operand.getDefiningOp<ub::PoisonOp>())
        continue;
      OpBuilder b(call);
      call.setOperand(param.getArgNumber(),
                      ub::PoisonOp::create(b, call.getLoc(), param.getType()));
      ++changed;
    }
  });
  return changed;
}

struct Prune : idr::impl::IdrPruneBase<Prune> {
  void runOnOperation() override {
    unsigned guarded = guardUnreadParameters(getOperation());
    numPoisoned += guarded;
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
    numEmptied += unreachable.size();
    if (unreachable.empty() && !guarded)
      markAllAnalysesPreserved();
  }
};

} // namespace
