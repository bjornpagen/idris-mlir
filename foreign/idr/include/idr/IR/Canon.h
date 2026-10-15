// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The canonicalizations of the dialect's ops besides their members: the
// patterns of idr.match and idr.match_lit (a match rebuilt, the values a
// consumer folds against, merging, case-of-case and sinking), the helpers
// of the constructor and field hooks, and output's patterns. The
// hooks that add or call them (MatchOp::getCanonicalizationPatterns, ...)
// are one line each. No pattern here keeps anything between attempts: a
// canonicalizer shares one frozen set among every function it runs on at
// once, and leaves the rewriter's listener to itself.

#ifndef IDR_IR_CANON_H
#define IDR_IR_CANON_H

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/ADT/iterator_range.h"

#include <memory>

namespace idr {
struct CalleeEffects;
} // namespace idr

namespace idr::canon {

// A pattern that moves an op across others, and so asks what each does, a
// call's included (sinking, case-of-case, an element's update): a call does
// what `callees` says its callee does, or anything when it has no table.
// The hooks add each with none, as upstream's canonicalizer runs them; the
// canonicalizer of a pipeline that has the program's table gives each it
// collected that table before it freezes them (bindCallees), so the table
// is built once per run of the pipeline and no attempt looks a callee up
// any other way.
class CalleePattern : public mlir::RewritePattern {
public:
  // The label every such pattern carries, and no other pattern.
  static constexpr llvm::StringLiteral kLabel = "idr-callee-effects";

  // This pattern, its calls read through `callees`.
  virtual std::unique_ptr<CalleePattern> withCallees(const CalleeEffects *callees) const = 0;

protected:
  // A pattern rooted at ops named `root`, or tried at every op.
  CalleePattern(llvm::StringRef root, llvm::StringRef name, mlir::MLIRContext *context,
                const CalleeEffects *callees)
      : RewritePattern(root, mlir::PatternBenefit(1), context), callees(callees) {
    setDebugName(name);
    addDebugLabels(kLabel);
  }
  CalleePattern(MatchAnyOpTypeTag any, llvm::StringRef name, mlir::MLIRContext *context,
                const CalleeEffects *callees)
      : RewritePattern(any, mlir::PatternBenefit(1), context), callees(callees) {
    setDebugName(name);
    addDebugLabels(kLabel);
  }

  const CalleeEffects *const callees;

  // Tells the driver to try again the ops of `ops`, a stretch of one block,
  // whose pattern asks of the ops between them and a partner whether they
  // only compute: a match (a value sinks into it, a consumer is raised
  // into it), a consumer of a match's result, and an array write (it and
  // its read become an update). A rewrite that moves an op doing more than
  // compute out from between such an op and its partner calls it for the
  // ops it moved across: the answer there changed, though neither the op
  // nor its partner did, and the driver tells only the ops a rewrite
  // changes. An op the rewrite moves something into is told already.
  static void retryBetween(mlir::PatternRewriter &rewriter,
                           llvm::iterator_range<mlir::Block::iterator> ops);
};

// Each pattern of `patterns` that asks what a call does, given `callees`
// in place of what it had (lib/IR/Canon/Callees.cpp).
void bindCallees(mlir::RewritePatternSet &patterns, const CalleeEffects *callees);

// The patterns of idr.match, after upstream's region patterns, and those
// tried at every op that move values and consumers into matches.
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
// follows the element's update, idr.array.update, tried at the write and at
// the read: CalleePatterns, added with no table.
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
// default last if there is one, inserted right before `op`, which it is to
// replace. A case is copied as the match holds it: a literal, or a
// constructor's tag.
template <typename Match>
Match rebuildMatch(mlir::RewriterBase &rewriter, Match op, mlir::TypeRange types,
                   llvm::ArrayRef<unsigned> cases, llvm::ArrayRef<mlir::Region *> regions);
// The match `match`, an idr.match or idr.match_lit, with `types` as
// results, inserted before it, which takes over its cases and regions. The
// caller replaces the old match's uses and erases it. Any other op is an
// internal error.
mlir::Operation *rebuildMatch(mlir::RewriterBase &rewriter, mlir::Operation *match,
                              mlir::TypeRange types);
// Identical regions merge.
template <typename Match>
void addMerge(mlir::RewritePatternSet &results, mlir::MLIRContext *context);
// Case-of-case: a consumer of a match's result moves into its regions. A
// CalleePattern tried at every op, added once, with no table.
void addCaseOfCase(mlir::RewritePatternSet &results, mlir::MLIRContext *context);
// A value only a match's regions use moves into them. A CalleePattern
// tried at every op, added once, with no table.
void addSink(mlir::RewritePatternSet &results, mlir::MLIRContext *context);

extern template MatchOp rebuildMatch<MatchOp>(mlir::RewriterBase &, MatchOp, mlir::TypeRange,
                                              llvm::ArrayRef<unsigned>,
                                              llvm::ArrayRef<mlir::Region *>);
extern template MatchLitOp rebuildMatch<MatchLitOp>(mlir::RewriterBase &, MatchLitOp,
                                                    mlir::TypeRange, llvm::ArrayRef<unsigned>,
                                                    llvm::ArrayRef<mlir::Region *>);
extern template void addMerge<MatchOp>(mlir::RewritePatternSet &, mlir::MLIRContext *);
extern template void addMerge<MatchLitOp>(mlir::RewritePatternSet &, mlir::MLIRContext *);

} // namespace idr::canon

#endif // IDR_IR_CANON_H
