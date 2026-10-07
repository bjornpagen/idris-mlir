// idr.specialize:specializer: idr-specialize's state for one run: the clone
// table, and the binding times found when the run starts. One run raises,
// then specializes, every call of every function, and of every clone made
// on the way.
export module idr.specialize:specializer;

import idr.mlir;
import idr.dialect;
import idr.graph;

import :bindingtimes;
import :clones;

using namespace mlir;

export namespace idr::specialize {

// The largest static value (unrollSize) a decreasing or bounded parameter
// is unrolled on. Unrolling exists to take small, partially static data off
// the heap (`Vect 3 Double`); a larger value stays data.
constexpr uint64_t kUnrollLimit = 32;

struct Statistics {
  uint64_t clones = 0;
  uint64_t raised = 0;
  uint64_t shared = 0;
  // The static arguments specialized on, by the binding time of their
  // parameter.
  uint64_t free = 0;
  uint64_t fixed = 0;
  uint64_t decreasing = 0;
  uint64_t bounded = 0;
};

// The single consumer of a call's result that raising moves into a clone of
// the callee: the elimination that is all its one use does with it.
using Consumer = Elimination;

class Specializer {
public:
  explicit Specializer(mlir::ModuleOp module);

  // Raises and specializes the calls of every function, and of every clone
  // it makes; fails once a budget is spent.
  mlir::LogicalResult run();

  Statistics stats;

private:
  // Raising (:raise): the call of a clone that replaces `call` and the
  // consumer of its result, or null.
  mlir::FailureOr<mlir::func::CallOp> raise(mlir::func::CallOp call);
  std::optional<Consumer> consumerOf(mlir::func::CallOp call, mlir::func::FuncOp callee);
  mlir::FailureOr<mlir::func::FuncOp> makeRaised(mlir::func::FuncOp callee,
                                                 mlir::func::CallOp call, Consumer c,
                                                 mlir::Attribute key);

  // Specialization (:specialization).
  mlir::LogicalResult specialize(mlir::func::CallOp call);

  void canonicalize(mlir::func::FuncOp fn);

  mlir::ModuleOp module;
  CloneTable clones;
  BindingTimes times;
  std::optional<mlir::FrozenRewritePatternSet> patterns;
  llvm::SmallVector<mlir::func::FuncOp> work;
};

} // namespace idr::specialize

namespace idr::specialize {

Specializer::Specializer(ModuleOp root)
    : module(root), clones(root), times(root, clones.symbols()) {}

LogicalResult Specializer::run() {
  // The functions present when the run starts were read once, before
  // anything changed. A clone is made during the run, and its calls are
  // what canonicalization left, so they are read when the clone is reached.
  idr::graph::References references(module, clones.symbols());
  llvm::append_range(work, module.getOps<func::FuncOp>());
  const size_t known = work.size();
  for (size_t i = 0; i < work.size(); ++i) {
    SmallVector<func::CallOp> calls;
    if (i < known) {
      for (const idr::graph::References::Site &site : references.of(work[i]))
        if (auto call = dyn_cast<func::CallOp>(site.at))
          calls.push_back(call);
    } else {
      work[i].walk([&](func::CallOp call) { calls.push_back(call); });
    }
    for (func::CallOp call : calls) {
      FailureOr<func::CallOp> raised = raise(call);
      if (failed(raised))
        return failure();
      // The raised call, if any, is the one to specialize.
      if (failed(specialize(*raised ? *raised : call)))
        return failure();
    }
  }
  return success();
}

void Specializer::canonicalize(func::FuncOp fn) {
  if (!patterns) {
    MLIRContext *ctx = module.getContext();
    RewritePatternSet set(ctx);
    for (Dialect *dialect : ctx->getLoadedDialects())
      dialect->getCanonicalizationPatterns(set);
    for (RegisteredOperationName op : ctx->getRegisteredOperations())
      op.getCanonicalizationPatterns(set, ctx);
    patterns.emplace(std::move(set));
  }
  (void)applyPatternsGreedily(fn, *patterns);
}

} // namespace idr::specialize
