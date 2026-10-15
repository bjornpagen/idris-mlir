// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Phase 1 of idr-lower: matches become scf, still on idr types.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/Conversion/Matches.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/PatternMatch.h"

#include <optional>

using namespace mlir;

namespace idr::conversion {

namespace {

// Moves the body of `from` into `into`, a new block of the op that replaces
// the match, whose results are `results`; `args` stand for the body's
// arguments. An idr.yield becomes scf.yield, and a ub.unreachable (after
// idr.crash) yields poison, which is never used. The terminator is replaced
// while it is still the match's, which the walk driver lets a pattern erase.
void moveBody(RewriterBase &rewriter, Region &from, Block *into, ValueRange args,
              TypeRange results) {
  Operation *terminator = from.front().getTerminator();
  rewriter.setInsertionPoint(terminator);
  if (auto yield = dyn_cast<YieldOp>(terminator)) {
    rewriter.replaceOpWithNewOp<scf::YieldOp>(yield, yield.getResults());
  } else {
    SmallVector<Value> poison;
    for (Type type : results)
      poison.push_back(ub::PoisonOp::create(rewriter, terminator->getLoc(), type));
    rewriter.replaceOpWithNewOp<scf::YieldOp>(terminator, poison);
  }
  rewriter.mergeBlocks(&from.front(), into, args);
}

// A region of a match and what its arguments stand for: the fields of the
// constructor `ctor`, or, for the default region, which has none, the
// scrutinee itself.
struct Arm {
  Region &region;
  std::optional<Tag> ctor;
};

// What `arm`'s arguments stand for, read from the scrutinee's value at the
// end of `into`, each held as the region binds it.
SmallVector<Value> readFields(RewriterBase &rewriter, const Arm &arm, Block *into, Value value) {
  rewriter.setInsertionPointToEnd(into);
  SmallVector<Value> fields;
  for (BlockArgument field : arm.region.front().getArguments()) {
    Value read = value;
    if (arm.ctor)
      read = FieldOp::create(rewriter, field.getLoc(), value, *arm.ctor, field.getArgNumber());
    fields.push_back(heldAs(rewriter, field.getLoc(), read, field.getType()));
  }
  return fields;
}

// The tag selects the case; the default is the match's default or, when
// Idris proved the other constructors impossible, its last case.
void lowerMatch(RewriterBase &rewriter, MatchOp op) {
  Location loc = op.getLoc();
  // A linear scrutinee is used here, once, and its regions read the value.
  rewriter.setInsertionPoint(op);
  Value scrutinee =
      heldAs(rewriter, loc, op.getScrutinee(), unrestricted(op.getScrutinee().getType()));
  SmallVector<Arm> cases;
  for (unsigned i = 0, e = static_cast<unsigned>(op.getCases().size()); i < e; ++i)
    cases.push_back({op.getCaseRegion(i), op.getCaseTag(i)});
  Arm fallback = op.getDefaultRegion() ? Arm{*op.getDefaultRegion(), std::nullopt}
                                       : cases.pop_back_val();
  SmallVector<int64_t> tags = llvm::map_to_vector(
      cases, [](const Arm &arm) -> int64_t { return static_cast<uint32_t>(*arm.ctor); });
  Value tag = TagOp::create(rewriter, loc, scrutinee);
  Value index = arith::IndexCastOp::create(rewriter, loc, rewriter.getIndexType(), tag);
  TypeRange results = op.getResultTypes();
  auto switchOp = scf::IndexSwitchOp::create(rewriter, loc, results, index, tags,
                                             static_cast<unsigned>(cases.size()));
  auto move = [&](const Arm &arm, Region &to) {
    Block *into = rewriter.createBlock(&to);
    SmallVector<Value> fields = readFields(rewriter, arm, into, scrutinee);
    moveBody(rewriter, arm.region, into, fields, results);
  };
  for (auto [arm, to] : llvm::zip_equal(cases, switchOp.getCaseRegions()))
    move(arm, to);
  move(fallback, switchOp.getDefaultRegion());
  rewriter.replaceOp(op, switchOp.getResults());
}

// An integer key selects its case through scf.index_switch on the key's bits,
// zero-extended; a string or big key is compared in turn.
void lowerMatchLit(RewriterBase &rewriter, MatchLitOp op) {
  Location loc = op.getLoc();
  Value scrutinee = op.getScrutinee();
  TypeRange results = op.getResultTypes();
  unsigned cases = static_cast<unsigned>(op.getCases().size());
  rewriter.setInsertionPoint(op);
  auto integer = dyn_cast<IntegerType>(scrutinee.getType());
  if (integer || cases == 0) {
    Value index;
    if (!integer) {
      index = arith::ConstantIndexOp::create(rewriter, loc, 0);
    } else {
      Value wide = scrutinee;
      if (integer.getWidth() < 64)
        wide = arith::ExtUIOp::create(rewriter, loc, rewriter.getI64Type(), scrutinee);
      index = arith::IndexCastUIOp::create(rewriter, loc, rewriter.getIndexType(), wide);
    }
    SmallVector<int64_t> keys;
    for (Attribute key : op.getCases())
      keys.push_back(static_cast<int64_t>(cast<IntegerAttr>(key).getValue().getZExtValue()));
    auto switchOp = scf::IndexSwitchOp::create(rewriter, loc, results, index, keys, cases);
    for (unsigned i = 0; i < cases; ++i)
      moveBody(rewriter, op.getCaseRegion(i), rewriter.createBlock(&switchOp.getCaseRegions()[i]),
               {}, results);
    moveBody(rewriter, *op.getDefaultRegion(), rewriter.createBlock(&switchOp.getDefaultRegion()),
             {}, results);
    rewriter.replaceOp(op, switchOp.getResults());
    return;
  }
  // case k0 {A} case k1 {B} default {C} is
  // if s == k0 then A else (if s == k1 then B else C), each comparison made
  // only where the one before failed.
  scf::IfOp first, previous;
  for (unsigned i = 0; i < cases; ++i) {
    if (previous)
      rewriter.setInsertionPointToStart(rewriter.createBlock(&previous.getElseRegion()));
    else
      rewriter.setInsertionPoint(op);
    Value literal = ConstantOp::create(rewriter, loc, scrutinee.getType(), op.getCases()[i]);
    auto eq = CmpPredicate::eq;
    Value equal = isa<StrType>(scrutinee.getType())
                      ? Value(StrCmpOp::create(rewriter, loc, eq, scrutinee, literal))
                      : Value(BigCmpOp::create(rewriter, loc, eq, scrutinee, literal));
    auto branch = scf::IfOp::create(rewriter, loc, results, equal, /*addThenBlock=*/false,
                                    /*addElseBlock=*/false);
    if (previous) {
      rewriter.setInsertionPointAfter(branch);
      scf::YieldOp::create(rewriter, loc, branch.getResults());
    } else {
      first = branch;
    }
    moveBody(rewriter, op.getCaseRegion(i), rewriter.createBlock(&branch.getThenRegion()), {},
             results);
    previous = branch;
  }
  moveBody(rewriter, *op.getDefaultRegion(), rewriter.createBlock(&previous.getElseRegion()), {},
           results);
  rewriter.replaceOp(op, first.getResults());
}

struct LowerMatch : OpRewritePattern<MatchOp> {
  using OpRewritePattern::OpRewritePattern;
  LogicalResult matchAndRewrite(MatchOp op, PatternRewriter &rewriter) const override {
    lowerMatch(rewriter, op);
    return success();
  }
};

struct LowerMatchLit : OpRewritePattern<MatchLitOp> {
  using OpRewritePattern::OpRewritePattern;
  LogicalResult matchAndRewrite(MatchLitOp op, PatternRewriter &rewriter) const override {
    lowerMatchLit(rewriter, op);
    return success();
  }
};

} // namespace

void populateMatchPatterns(RewritePatternSet &patterns) {
  patterns.add<LowerMatch, LowerMatchLit>(patterns.getContext());
}

} // namespace idr::conversion
