// One run of idr-specialize: every call of every function, and of every
// clone made on the way, is raised, then specialized.

#include "Specialize/Specializer.h"

#include "mlir/Transforms/GreedyPatternRewriteDriver.h"

using namespace mlir;

namespace idr::specialize {

Specializer::Specializer(ModuleOp root)
    : module(root), clones(root), times(root, clones.symbols()) {}

LogicalResult Specializer::run() {
  llvm::append_range(work, module.getOps<func::FuncOp>());
  for (size_t i = 0; i < work.size(); ++i) {
    SmallVector<func::CallOp> calls;
    work[i].walk([&](func::CallOp call) { calls.push_back(call); });
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
