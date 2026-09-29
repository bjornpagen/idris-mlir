// Phase 1 of idr-lower: matches become scf, still on idr types.

#include "Lower/Patterns.h"

#include "mlir/IR/PatternMatch.h"

using namespace mlir;

namespace idr::lower {

namespace {

// Moves the body of `from` to the empty region `to`, whose op produces
// `results`: an idr.yield becomes scf.yield, and a ub.unreachable (after
// idr.crash) yields poison, which is never used.
void moveRegion(RewriterBase &rewriter, Region &from, Region &to, TypeRange results) {
  rewriter.inlineRegionBefore(from, to, to.end());
  Operation *terminator = to.front().getTerminator();
  rewriter.setInsertionPoint(terminator);
  if (auto yield = dyn_cast<YieldOp>(terminator)) {
    rewriter.replaceOpWithNewOp<scf::YieldOp>(yield, yield.getResults());
    return;
  }
  SmallVector<Value> poison;
  for (Type type : results)
    poison.push_back(ub::PoisonOp::create(rewriter, terminator->getLoc(), type));
  rewriter.replaceOpWithNewOp<scf::YieldOp>(terminator, poison);
}

// A case region's fields become idr.field reads of the scrutinee at its
// start; a field the region binds linearly enters its linear type.
void readFields(RewriterBase &rewriter, Region &region, Value scrutinee, FlatSymbolRefAttr ctor) {
  Block &block = region.front();
  rewriter.setInsertionPointToStart(&block);
  CtorOp decl = lookupCtor(lookupData(region.getParentOp(), scrutinee.getType()), ctor.getValue());
  for (BlockArgument field : block.getArguments()) {
    Type type = decl.getFieldType(field.getArgNumber());
    Value value = FieldOp::create(rewriter, field.getLoc(), type, scrutinee, ctor,
                                  rewriter.getI64IntegerAttr(field.getArgNumber()));
    if (type != field.getType())
      value = LinEnterOp::create(rewriter, field.getLoc(), field.getType(), value);
    rewriter.replaceAllUsesWith(field, value);
  }
  block.eraseArguments(0, block.getNumArguments());
}

// The tag selects the case; the default is the match's default or, when
// Idris proved the other constructors impossible, its last case.
void lowerMatch(RewriterBase &rewriter, MatchOp op) {
  Location loc = op.getLoc();
  Value scrutinee = op.getScrutinee();
  DataOp data = lookupData(op, scrutinee.getType());
  auto names = llvm::to_vector(op.getCases().getAsRange<FlatSymbolRefAttr>());
  for (auto [i, name] : llvm::enumerate(names))
    readFields(rewriter, op.getCaseRegion(static_cast<unsigned>(i)), scrutinee, name);
  unsigned cases = static_cast<unsigned>(names.size());
  Region *fallback = op.getDefaultRegion();
  if (!fallback)
    fallback = &op.getCaseRegion(--cases);
  SmallVector<int64_t> tags;
  for (unsigned i = 0; i < cases; ++i)
    tags.push_back(static_cast<int64_t>(lookupCtor(data, names[i].getValue()).getTag()));
  rewriter.setInsertionPoint(op);
  Value tag = TagOp::create(rewriter, loc, scrutinee);
  Value index = arith::IndexCastOp::create(rewriter, loc, rewriter.getIndexType(), tag);
  auto switchOp =
      scf::IndexSwitchOp::create(rewriter, loc, op.getResultTypes(), index, tags, cases);
  for (unsigned i = 0; i < cases; ++i)
    moveRegion(rewriter, op.getCaseRegion(i), switchOp.getCaseRegions()[i], op.getResultTypes());
  moveRegion(rewriter, *fallback, switchOp.getDefaultRegion(), op.getResultTypes());
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
      moveRegion(rewriter, op.getCaseRegion(i), switchOp.getCaseRegions()[i], results);
    moveRegion(rewriter, *op.getDefaultRegion(), switchOp.getDefaultRegion(), results);
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
    Value equal = isa<StrType>(scrutinee.getType())
                      ? Value(StrCmpOp::create(rewriter, loc, CmpPredicate::eq, scrutinee, literal))
                      : Value(BigCmpOp::create(rewriter, loc, CmpPredicate::eq, scrutinee, literal));
    auto branch = scf::IfOp::create(rewriter, loc, results, equal, /*addThenBlock=*/false,
                                    /*addElseBlock=*/false);
    if (previous) {
      rewriter.setInsertionPointAfter(branch);
      scf::YieldOp::create(rewriter, loc, branch.getResults());
    } else {
      first = branch;
    }
    moveRegion(rewriter, op.getCaseRegion(i), branch.getThenRegion(), results);
    previous = branch;
  }
  moveRegion(rewriter, *op.getDefaultRegion(), previous.getElseRegion(), results);
  rewriter.replaceOp(op, first.getResults());
}

} // namespace

void lowerMatches(ModuleOp module) {
  SmallVector<Operation *> matches;
  module.walk([&](Operation *op) {
    if (isa<MatchOp, MatchLitOp>(op))
      matches.push_back(op);
  });
  IRRewriter rewriter(module.getContext());
  for (Operation *op : matches) {
    if (auto match = dyn_cast<MatchOp>(op))
      lowerMatch(rewriter, match);
    else
      lowerMatchLit(rewriter, cast<MatchLitOp>(op));
  }
}

} // namespace idr::lower
