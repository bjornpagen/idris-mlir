// idr.eval:calls: the closed calls idr-eval runs, and what it knows of
// them across its runs.
export module idr.eval:calls;

import idr.mlir;

import :child;

export namespace idr::eval {

// A call is known by its callee and its constant arguments; a closure's
// captures come before the arguments of its application.
using Key = std::pair<mlir::Attribute, mlir::Attribute>;

struct Outcome {
  llvm::SmallVector<mlir::Attribute> results;
  // The call crashed or did not finish: it stays, to run at runtime.
  bool stays = false;
};

// Results for the compilation, which the simplify loop runs round after
// round with idr-eval. A call that stays is known too, so it is not run
// again.
using Cache = llvm::DenseMap<Key, Outcome>;

// What one run counted, for the pass's statistics.
struct Statistics {
  uint64_t evaluated = 0;
  uint64_t stayedCrash = 0;
  uint64_t stayedBudget = 0;
  uint64_t stayedLarge = 0;
  uint64_t cacheHits = 0;
};

// How the pass runs a pipeline of its own on an op (Pass::runPipeline),
// which the lowering of a round's calls is.
using RunPipeline =
    llvm::function_ref<mlir::LogicalResult(mlir::OpPassManager &, mlir::Operation *)>;

} // namespace idr::eval

// What evaluation and its rounds share.
namespace idr::eval {

// How a call runs: what it may spend (ticks, counted where code enters a
// function or goes round a loop, bytes of arena and bytes of stack), and
// how its remark says it did not finish.
struct Meter {
  Budget budget;
  const char *unfinished;
};

struct Call {
  mlir::Operation *op;
  mlir::func::FuncOp callee;
  mlir::ArrayAttr args;
  const Meter *meter;
};

} // namespace idr::eval
