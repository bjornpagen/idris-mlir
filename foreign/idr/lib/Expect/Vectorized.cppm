// vectorized: after idr-vectorize, some loop computes on vectors, and none
// over words with a parallel dimension stays scalar.
export module idr.expect:vectorized;

import idr.mlir;

import :report;
import :roots;

using namespace mlir;

namespace idr::expect {

// A body the vectorizer takes: words alone, computed by arith and math ops
// and the loop's own indices.
static bool wordsAlone(linalg::GenericOp op) {
  for (Operation &inner : op.getRegion().front()) {
    if (isa<linalg::IndexOp, linalg::YieldOp>(inner))
      continue;
    StringRef dialect = inner.getDialect() ? inner.getDialect()->getNamespace() : "";
    if (inner.getNumRegions() != 0 || (dialect != "arith" && dialect != "math"))
      return false;
  }
  return true;
}

// After idr-vectorize, in the function the argument names or anywhere, some
// loop computes on vectors, and no linalg.generic with a parallel dimension
// and a body of words alone is left scalar.
export LogicalResult vectorized(ModuleOp module, StringRef function) {
  constexpr StringRef property = "vectorized";
  SmallVector<Operation *> roots = rootsOf(module, function, property);
  if (roots.empty())
    return failure();
  bool held = true, vectors = false;
  for (Operation *root : roots)
    root->walk([&](Operation *op) {
      if (isa_and_nonnull<vector::VectorDialect>(op->getDialect()))
        vectors = true;
      auto generic = dyn_cast<linalg::GenericOp>(op);
      if (!generic || llvm::none_of(generic.getIteratorTypesArray(), linalg::isParallelIterator) ||
          !wordsAlone(generic))
        return;
      fail(op->getLoc(), property) << "a loop over words with a parallel dimension stayed scalar in "
                                   << where(op);
      held = false;
    });
  if (!vectors) {
    fail(roots.front()->getLoc(), property) << "no loop computes on vectors"
                                            << (function.empty() ? "" : " in ") << function;
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
