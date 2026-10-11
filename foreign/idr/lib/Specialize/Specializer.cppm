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
  // What raising produced: the call to specialize, and the function it
  // names. A null call means `call` was not raised.
  struct Raised {
    mlir::func::CallOp call;
    mlir::func::FuncOp callee;
  };

  // Raising (:raise). `callee` is the function `call` names, resolved when
  // the calls were read.
  mlir::FailureOr<Raised> raise(mlir::func::CallOp call, mlir::func::FuncOp callee);
  std::optional<Consumer> consumerOf(mlir::func::CallOp call, mlir::func::FuncOp callee);
  mlir::FailureOr<mlir::func::FuncOp> makeRaised(mlir::func::FuncOp callee,
                                                 mlir::func::CallOp call, Consumer c,
                                                 mlir::Attribute key);

  // Specialization (:specialization). `callee` is the function `call` names,
  // the same resolution raising used.
  mlir::LogicalResult specialize(mlir::func::CallOp call, mlir::func::FuncOp callee);

  void canonicalize(mlir::func::FuncOp fn);

  mlir::ModuleOp module;
  CloneTable clones;
  // The references of the functions present when the run starts, read once
  // for the binding times and for the calls. Valid until those functions
  // change; each function's calls are taken from it before that function
  // is rewritten.
  idr::graph::References references;
  BindingTimes times;
  std::optional<mlir::FrozenRewritePatternSet> patterns;
  llvm::SmallVector<mlir::func::FuncOp> work;
};

} // namespace idr::specialize

namespace idr::specialize {

Specializer::Specializer(ModuleOp root)
    : module(root), clones(root), references(root, clones.symbols()),
      times(root, clones, references) {}

LogicalResult Specializer::run() {
  // The functions present when the run starts were read once, with the
  // binding times, before anything changed. That read resolved each call's
  // callee. Raising and specializing both use it: the name still names that
  // function, since nothing erases or renames a symbol, so a call does not
  // look its callee up again. A clone is made during the run, and its calls
  // are what canonicalization left, so each of those callees is resolved
  // once when the clone is reached and then used the same way.
  llvm::append_range(work, module.getOps<func::FuncOp>());
  const size_t known = work.size();
  for (size_t i = 0; i < work.size(); ++i) {
    SmallVector<std::pair<func::CallOp, func::FuncOp>> calls;
    if (i < known) {
      for (const idr::graph::References::Site &site : references.of(work[i]))
        if (auto call = dyn_cast<func::CallOp>(site.at))
          calls.push_back({call, site.target});
    } else {
      work[i].walk([&](func::CallOp call) {
        if (auto callee = clones.symbols().lookup<func::FuncOp>(call.getCalleeAttr().getAttr()))
          calls.push_back({call, callee});
      });
    }
    for (auto [call, callee] : calls) {
      FailureOr<Raised> raised = raise(call, callee);
      if (failed(raised))
        return failure();
      // The raised call, if any, is the one to specialize, and it names the
      // clone raising just called.
      const Raised &done = *raised;
      if (failed(specialize(done.call ? done.call : call, done.call ? done.callee : callee)))
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
