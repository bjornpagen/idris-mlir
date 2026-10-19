// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A force by name: the exchange of a memo cell's state that nothing can
// tell from a call of its label, which then runs on the cell's captures as
// a call would, and the value it would move in goes nowhere.
//
// - A suspension built here whose one use is its force has no other
//   reference: no reader ever sees the cell Running or Forced.
// - A static suspension, a constant, forced in the program's root, where
//   its label performs no IO. No call reaches the root, so no run of the
//   suspension is in progress there and each op of the root runs once; a
//   label run again computes the value the cell would have held, and only
//   its IO could tell how many times it ran. The match of the cell's state
//   there takes the case of the label it was built with.
//
// The cell and the exchange are then dead, and with them every name the
// cell's label held alive, as `(>>)`'s delayed second action is in a do
// block.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Canon.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"

#include "mlir/IR/Matchers.h"
#include "mlir/IR/PatternMatch.h"

using namespace mlir;
using namespace idr;

namespace {

// Whether `op` is in its program's root.
bool inRoot(Operation *op) {
  auto fn = op->getParentOfType<FuncOp>();
  return fn && fn.isRoot();
}

// The static suspension `cell` is, when it is a constant forced by name
// here: in the root, by an exchange that performs no IO, its captures
// constants an op can hold.
std::optional<ConAttr> staticByName(Value cell, MemoRunOp run) {
  ConAttr built;
  if (!matchPattern(cell, m_Constant(&built)) || built.getTag() != run.getTag() ||
      !inRoot(run) || performsIO(run))
    return std::nullopt;
  for (auto [field, capture] : llvm::zip_equal(built.getFields(), run.getCaptures()))
    if (!canon::buildable(field, unrestricted(capture.getType())))
      return std::nullopt;
  return built;
}

// The captures of the static suspension `built`, at the types `bound`.
SmallVector<Value> capturesOf(PatternRewriter &rewriter, Location loc, ConAttr built,
                              ValueRange bound) {
  Dialect *dialect = rewriter.getContext()->getLoadedDialect<IdrDialect>();
  SmallVector<Value> captures;
  for (auto [field, arg] : llvm::zip_equal(built.getFields(), bound)) {
    Type type = arg.getType();
    Operation *made = dialect->materializeConstant(rewriter, field, unrestricted(type), loc);
    captures.push_back(heldAs(rewriter, loc, made->getResult(0), type));
  }
  return captures;
}

struct ForceByName : OpRewritePattern<MemoRunOp> {
  using OpRewritePattern::OpRewritePattern;

  LogicalResult matchAndRewrite(MemoRunOp run, PatternRewriter &rewriter) const override {
    Block *body = run.getBody();
    // A label that never returns ends its region in no yield, and stays.
    if (!isa<ArrayYieldOp>(body->getTerminator()))
      return failure();
    SmallVector<Value> captures;
    Operation *fresh = nullptr;
    if (auto built = run.getCell().getDefiningOp<ConOp>();
        built && built.getTag() == run.getTag() && built.getResult().hasOneUse()) {
      fresh = built;
      for (auto [field, capture] : llvm::zip_equal(built.getFields(), body->getArguments()))
        captures.push_back(heldAs(rewriter, run.getLoc(), field, capture.getType()));
    } else if (std::optional<ConAttr> constant = staticByName(run.getCell(), run)) {
      captures = capturesOf(rewriter, run.getLoc(), *constant, body->getArguments());
    } else {
      return failure();
    }
    // Inlined, the region's arguments are the captures, in what it yields
    // too.
    Operation *yield = body->getTerminator();
    rewriter.inlineBlockBefore(body, run, captures);
    SmallVector<Value> outs(yield->getOperands().drop_front());
    rewriter.eraseOp(yield);
    rewriter.replaceOp(run, outs);
    if (fresh)
      rewriter.eraseOp(fresh);
    return success();
  }
};

// The match of a static suspension's state in the root, where each force
// of it in the case of the label it was built with is by name: that case.
struct StaticCase : OpRewritePattern<MatchOp> {
  using OpRewritePattern::OpRewritePattern;

  LogicalResult matchAndRewrite(MatchOp match, PatternRewriter &rewriter) const override {
    ConAttr built;
    if (!matchPattern(match.getScrutinee(), m_Constant(&built)) || !built.getData().isMemo())
      return failure();
    auto cases = match.getCases();
    const auto *at = llvm::find(cases, static_cast<int32_t>(built.getTag()));
    if (at == cases.end())
      return failure();
    Region &taken = match.getCaseRegion(static_cast<unsigned>(at - cases.begin()));
    bool byName = true;
    taken.walk([&](MemoRunOp run) {
      byName = byName && (run.getCell() != match.getScrutinee() ||
                          staticByName(run.getCell(), run).has_value());
    });
    Block &body = taken.front();
    if (!byName || !inRoot(match) ||
        !llvm::all_of_zip(built.getFields(), body.getArguments(), [](Attribute field, Value arg) {
          return canon::buildable(field, unrestricted(arg.getType()));
        }))
      return failure();
    SmallVector<Value> captures = capturesOf(rewriter, match.getLoc(), built, body.getArguments());
    Operation *yield = body.getTerminator();
    rewriter.inlineBlockBefore(&body, match, captures);
    SmallVector<Value> results(yield->getOperands());
    rewriter.eraseOp(yield);
    rewriter.replaceOp(match, results);
    return success();
  }
};

} // namespace

namespace idr::canon {

void addMemoRunPatterns(RewritePatternSet &results, MLIRContext *context) {
  results.add<ForceByName>(context);
}

void addStaticForcePatterns(RewritePatternSet &results, MLIRContext *context) {
  results.add<StaticCase>(context);
}

} // namespace idr::canon
