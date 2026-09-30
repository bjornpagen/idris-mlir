// What the canonicalizations of idr.match and idr.match_lit share: a match
// rebuilt with other results or regions, the values a consumer folds
// against, and the patterns of each concern, added per match op.
#pragma once

#include "idr/Idr.h"

#include "mlir/IR/PatternMatch.h"

namespace idr::canon {

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

// Whether the consumer holding `use` folds or canonicalizes, or is raised,
// once the operand it holds there is `value`.
bool feeds(mlir::Value value, mlir::OpOperand &use);

// Whether `consumer`, moved into every region of the match that defines
// `result`, meets in some region a value it folds or canonicalizes against.
bool meetsInSomeRegion(mlir::OpResult result, mlir::Operation *consumer);

// Identical regions merge (Merge.cc).
template <typename Match> void addMerge(mlir::RewritePatternSet &results, mlir::MLIRContext *context);

// Case-of-case: a consumer of a match's result moves into its regions
// (CaseOfCase.cc).
template <typename Match>
void addCaseOfCase(mlir::RewritePatternSet &results, mlir::MLIRContext *context);

// A value only a match's regions use moves into them (Sink.cc).
template <typename Match> void addSink(mlir::RewritePatternSet &results, mlir::MLIRContext *context);

} // namespace idr::canon
