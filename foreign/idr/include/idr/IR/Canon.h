// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The canonicalizations of the dialect's ops besides their members: the
// patterns of idr.match and idr.match_lit (a match rebuilt, the values a
// consumer folds against, merging, case-of-case and sinking), the helpers
// of the constructor and field hooks, and output's patterns. The
// hooks that add or call them (MatchOp::getCanonicalizationPatterns, ...)
// are one line each. No pattern here keeps anything between attempts:
// upstream's pass shares one frozen set among every function it runs on at
// once, and leaves the rewriter's listener to itself.

#ifndef IDR_IR_CANON_H
#define IDR_IR_CANON_H

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/PatternMatch.h"

namespace idr::canon {

// The patterns of idr.match, after upstream's region patterns.
void addMatchPatterns(mlir::RewritePatternSet &results, mlir::MLIRContext *context);
// The patterns of idr.match_lit, after upstream's region patterns.
void addMatchLitPatterns(mlir::RewritePatternSet &results, mlir::MLIRContext *context);
// Output fusion (the DRR patterns) and output of the empty string.
void addPutStrPatterns(mlir::RewritePatternSet &results, mlir::MLIRContext *context);
// The first character of a string being built, read off its builder.
void addStrHeadPatterns(mlir::RewritePatternSet &results, mlir::MLIRContext *context);
// The patterns of idr.io.put_list.
void addPutListPatterns(mlir::RewritePatternSet &results, mlir::MLIRContext *context);
// The pattern that makes a read of an element and the write of it that
// follows the element's update, idr.array.update.
void addMoveOutPatterns(mlir::RewritePatternSet &results, mlir::MLIRContext *context);

// A case region's arguments are its constructor's fields, read from the
// value the scrutinee entered its grade from and held as the region binds
// them; the default region's argument is the scrutinee itself.
mlir::Value readField(mlir::OpBuilder &builder, mlir::Location loc, mlir::Value value);
// A match on a linear value takes it apart, and stays: the value has no
// other reader to read its fields from.
mlir::LogicalResult readsPlainValue(mlir::Operation *op);

// Record eta: a constructor rebuilt from the fields of a value known to be
// that constructor is the value, or null.
mlir::Value eta(ConOp con);
// Whether a constant constructor, closure or suspension holds `value` in a
// field or capture of `type`.
bool buildable(mlir::Attribute value, mlir::Type type);

// Whether the consumer holding `use` folds or canonicalizes, or is raised
// or specialized, once the operand it holds there is `value`; not whether
// it merely holds it.
bool feeds(mlir::Value value, mlir::OpOperand &use);
// Whether `consumer`, moved into every region of the match that defines
// `result`, meets in some region, or in a region of a match such a region
// yields the result of, a value it folds or canonicalizes against.
bool meetsInSomeRegion(mlir::OpResult result, mlir::Operation *consumer);

// A match like `op`, with `types` as results, the cases of `op` at the
// positions `cases`, in that order, and the regions `regions` (moved), the
// default last if there is one. A case is copied as the match holds it: a
// literal, or a constructor's tag.
template <typename Match>
Match rebuildMatch(mlir::RewriterBase &rewriter, Match op, mlir::TypeRange types,
                   llvm::ArrayRef<unsigned> cases, llvm::ArrayRef<mlir::Region *> regions);
// The match `match`, an idr.match or idr.match_lit, with `types` as
// results, inserted before it, which takes over its cases and regions. The
// caller replaces the old match's uses and erases it.
mlir::Operation *rebuildMatch(mlir::RewriterBase &rewriter, mlir::Operation *match,
                              mlir::TypeRange types);
// Identical regions merge.
template <typename Match>
void addMerge(mlir::RewritePatternSet &results, mlir::MLIRContext *context);
// Case-of-case: a consumer of a match's result moves into its regions.
template <typename Match>
void addCaseOfCase(mlir::RewritePatternSet &results, mlir::MLIRContext *context);
// A value only a match's regions use moves into them.
template <typename Match>
void addSink(mlir::RewritePatternSet &results, mlir::MLIRContext *context);

extern template MatchOp rebuildMatch<MatchOp>(mlir::RewriterBase &, MatchOp, mlir::TypeRange,
                                              llvm::ArrayRef<unsigned>,
                                              llvm::ArrayRef<mlir::Region *>);
extern template MatchLitOp rebuildMatch<MatchLitOp>(mlir::RewriterBase &, MatchLitOp,
                                                    mlir::TypeRange, llvm::ArrayRef<unsigned>,
                                                    llvm::ArrayRef<mlir::Region *>);
extern template void addMerge<MatchOp>(mlir::RewritePatternSet &, mlir::MLIRContext *);
extern template void addMerge<MatchLitOp>(mlir::RewritePatternSet &, mlir::MLIRContext *);
extern template void addCaseOfCase<MatchOp>(mlir::RewritePatternSet &, mlir::MLIRContext *);
extern template void addCaseOfCase<MatchLitOp>(mlir::RewritePatternSet &, mlir::MLIRContext *);
extern template void addSink<MatchOp>(mlir::RewritePatternSet &, mlir::MLIRContext *);
extern template void addSink<MatchLitOp>(mlir::RewritePatternSet &, mlir::MLIRContext *);

} // namespace idr::canon

#endif // IDR_IR_CANON_H
