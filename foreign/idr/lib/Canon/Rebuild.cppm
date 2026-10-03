// idr.canon:rebuild: a match rebuilt with other results or regions, which
// every canonicalization that changes a match's shape makes.
export module idr.canon:rebuild;

import idr.mlir;

export namespace idr::canon {

// A match like `op`, with `types` as results, `cases` and the regions
// `regions` (moved), the default last if there is one.
template <typename Match>
Match rebuildMatch(mlir::PatternRewriter &rewriter, Match op, mlir::TypeRange types,
                   llvm::ArrayRef<mlir::Attribute> cases, llvm::ArrayRef<mlir::Region *> regions) {
  auto fresh = Match::create(rewriter, op.getLoc(), types, op.getScrutinee(),
                             rewriter.getArrayAttr(cases),
                             static_cast<unsigned>(regions.size()));
  fresh->setDiscardableAttrs(op->getDiscardableAttrDictionary());
  for (auto [to, from] : llvm::zip(fresh.getRegions(), regions))
    rewriter.inlineRegionBefore(*from, to, to.end());
  return fresh;
}

} // namespace idr::canon
