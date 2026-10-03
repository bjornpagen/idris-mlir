// idr.canonicalize:patterns: the patterns canonicalize collects.
export module idr.canonicalize:patterns;

import idr.mlir;

using namespace mlir;

export namespace idr::canonicalize {

// The canonicalization patterns of every loaded dialect and every
// registered op of `context`, of the dialects `filterDialects` names (all,
// when it names none), without `disabled` and, when it names any, only
// `enabled`. A dialect named that is not loaded is an error.
FailureOr<std::shared_ptr<const FrozenRewritePatternSet>>
collect(MLIRContext *context, llvm::ArrayRef<std::string> filterDialects,
        llvm::ArrayRef<std::string> disabled, llvm::ArrayRef<std::string> enabled) {
  llvm::DenseSet<TypeID> allowed;
  for (const std::string &name : filterDialects) {
    Dialect *dialect = context->getLoadedDialect(name);
    if (!dialect)
      return emitError(UnknownLoc::get(context))
             << "idr-canonicalize: filter-dialects names " << name << ", which is not loaded";
    allowed.insert(dialect->getTypeID());
  }
  auto isAllowed = [&](Dialect *dialect) {
    return allowed.empty() || allowed.contains(dialect->getTypeID());
  };
  RewritePatternSet owned(context);
  for (Dialect *dialect : context->getLoadedDialects())
    if (isAllowed(dialect))
      dialect->getCanonicalizationPatterns(owned);
  for (RegisteredOperationName op : context->getRegisteredOperations())
    if (isAllowed(&op.getDialect()))
      op.getCanonicalizationPatterns(owned, context);
  return std::shared_ptr<const FrozenRewritePatternSet>(
      std::make_shared<FrozenRewritePatternSet>(std::move(owned), disabled, enabled));
}

} // namespace idr::canonicalize
