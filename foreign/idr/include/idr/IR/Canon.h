// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The canonicalizations of the dialect's ops besides their members: the
// patterns of the matches (merging, case-of-case and sinking, each over
// MatchOpInterface), the values a consumer folds against, the helpers of
// the constructor and field hooks, and output's patterns. The hooks that
// add or call them (MatchOp::getCanonicalizationPatterns, ...) are one line
// each, and upstream's canonicalizer runs them. No pattern here keeps
// anything between attempts: a canonicalizer shares one frozen set among
// every function it runs on at once, and leaves the rewriter's listener to
// itself. What a call does is its own effects, which it declares as every
// op does, so no pattern here is given anything to read them through.

#ifndef IDR_IR_CANON_H
#define IDR_IR_CANON_H

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/ADT/iterator_range.h"

namespace idr::canon {

// Tells the driver to try again the ops of `ops`, a stretch of one block,
// whose pattern asks of the ops between them and a partner whether they
// only compute: a match (a value sinks into it, a consumer is raised into
// it), a consumer of a match's result, and an array write (it and its read
// become an update). A rewrite that moves an op doing more than compute
// out from between such an op and its partner calls it for the ops it
// moved across: the answer there changed, though neither the op nor its
// partner did, and the driver tells only the ops a rewrite changes. An op
// the rewrite moves something into is told already.
void retryBetween(mlir::PatternRewriter &rewriter,
                  llvm::iterator_range<mlir::Block::iterator> ops);

// The patterns of idr.memo.run, and the case a match of a static
// suspension's state takes in the root: a force nothing can tell from a
// call of its label is a call by name (Force.cpp).
void addMemoRunPatterns(mlir::RewritePatternSet &results, mlir::MLIRContext *context);
void addStaticForcePatterns(mlir::RewritePatternSet &results, mlir::MLIRContext *context);
// The patterns of idr.match, after upstream's region patterns, and those
// tried at every op that move values and consumers into matches.
void addMatchPatterns(mlir::RewritePatternSet &results, mlir::MLIRContext *context);
// The patterns of idr.match_lit, after upstream's region patterns.
void addMatchLitPatterns(mlir::RewritePatternSet &results, mlir::MLIRContext *context);
// Output of a string as the pieces its builder builds it of
// (StrBuilderOpInterface).
void addPutStrPatterns(mlir::RewritePatternSet &results, mlir::MLIRContext *context);
// The first character of a string being built, read off its builder.
void addStrHeadPatterns(mlir::RewritePatternSet &results, mlir::MLIRContext *context);
// The patterns of idr.io.put_list.
void addPutListPatterns(mlir::RewritePatternSet &results, mlir::MLIRContext *context);
// The pattern that makes a read of an element and the write of it that
// follows the element's update, idr.array.update, tried at the write and at
// the read.
void addMoveOutPatterns(mlir::RewritePatternSet &results, mlir::MLIRContext *context);

// A match's region replaces it: a case region's arguments are its
// constructor's fields, read from the scrutinee seen back through its
// linear positions to the earliest value held at quantity many, and held as
// the region binds them; the default region's argument is the scrutinee
// itself.
mlir::Value readField(mlir::OpBuilder &builder, mlir::Location loc, mlir::Value value);
// A match on a value that is linear at every position it passed takes it
// apart, and stays: the value has no other reader to read its fields from.
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

// Identical regions of the match ops named `root` merge.
void addMerge(mlir::RewritePatternSet &results, mlir::MLIRContext *context,
              llvm::StringRef root);
// Case-of-case: a consumer of a match's result moves into its regions.
// Tried at every op, added once.
void addCaseOfCase(mlir::RewritePatternSet &results, mlir::MLIRContext *context);
// A value only a match's regions use moves into them. Tried at every op,
// added once.
void addSink(mlir::RewritePatternSet &results, mlir::MLIRContext *context);

} // namespace idr::canon

#endif // IDR_IR_CANON_H
