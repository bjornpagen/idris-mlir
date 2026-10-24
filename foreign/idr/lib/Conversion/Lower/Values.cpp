// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The values of ours that are no cell of their own: a constant, which is
// static data or its components; poison, which may still be dropped; a
// select, of each component; and the region in which an erased equality
// holds, which runs once, in place, each value it rebinds re-packed where
// the equality changes the layout its type has.

#include "idr/Conversion/Lower/Lower.h"

#include "idr/IR/Grades.h"
#include "idr/Conversion/IdrPattern.h"
#include "idr/Conversion/StaticData.h"
#include "idr/Conversion/Words.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/UB/IR/UBOps.h"

using namespace mlir;

namespace idr::conversion {

namespace {

// The region in which an erased equality holds runs once, in place: the
// values forwarded into it are its arguments, each re-packed from its own
// type into the type the region binds it at, where the equality makes a
// closed index of an open one or an open one of a closed one; its yield
// is the op's results.
struct LowerAssume : IdrPattern<IndexAssumeOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(IndexAssumeOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    FailureOr<SmallVector<SmallVector<Type>>> converted =
        convertedResults(op, *getTypeConverter());
    if (failed(converted))
      return rewriter.notifyMatchFailure(op, "a result's type does not convert");
    SmallVector<Type> flat;
    for (ArrayRef<Type> components : *converted)
      llvm::append_range(flat, components);
    SmallVector<SmallVector<Value>> args;
    for (auto [forwarded, values, bound] : llvm::zip_equal(
             op.getForwarded(), adaptor.getForwarded(), op.getBody().front().getArgumentTypes()))
      args.push_back(repack(rewriter, loc, layouts, runtime, forwarded.getType(), bound, values,
                            takesOf(forwarded.getType())));
    auto run = scf::ExecuteRegionOp::create(rewriter, loc, flat);
    moveRegion(rewriter, *getTypeConverter(), op.getBody(), args, run.getRegion());
    rewriter.replaceOpWithMultiple(op, groupResults(run.getResults(), *converted));
    return success();
  }
};

// Strings, bigs and cells, memo cells among them, are static data, the
// globals made for them before any function is lowered; a constant in place
// is its components.
struct LowerConstant : IdrPattern<ConstantOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(ConstantOp op, OneToNOpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOpWithMultiple(op, {constantComponents(rewriter, op.getLoc(), layouts,
                                                           runtime.statics(), op.getValue(),
                                                           op.getType())});
    return success();
  }
};

// Poison may still be dropped, as what a function nobody reads is passed,
// or what a loop forwards on the path it does not take. Poison of a cell
// pointer is the static cell `nothing`: a cell, so every fact LLVM is told
// of a cell pointer holds of it, and static, so counting it changes
// nothing. Poison of any other value of ours is poison of each component,
// but for the counted ones, which are the runtime's empty value: a big's
// word, a sum's slot, an array's cell.
struct LowerPoison : IdrPattern<ub::PoisonOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(ub::PoisonOp op, OneToNOpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    Type type = op.getType();
    if (isCellPointer(type)) {
      rewriter.replaceOpWithMultiple(
          op, {SmallVector<Value>{staticAddress(rewriter, loc, runtime.statics().nothing())}});
      return success();
    }
    SmallVector<Value> out;
    for (const layout::Component &component : layouts.components(type))
      out.push_back(component.counted()
                        ? nullComponent(rewriter, loc, component.type)
                        : ub::PoisonOp::create(rewriter, loc, component.type).getResult());
    rewriter.replaceOpWithMultiple(op, {out});
    return success();
  }
};

// A select of a value of ours selects each of its components.
struct LowerSelect : IdrPattern<arith::SelectOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(arith::SelectOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Value cond = adaptor.getCondition().front();
    SmallVector<Value> out;
    for (auto [a, b] : llvm::zip_equal(adaptor.getTrueValue(), adaptor.getFalseValue()))
      out.push_back(arith::SelectOp::create(rewriter, op.getLoc(), cond, a, b));
    rewriter.replaceOpWithMultiple(op, {out});
    return success();
  }
};

} // namespace

void populateValuePatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                           const Layouts &layouts, Runtime &runtime) {
  patterns.add<LowerAssume, LowerConstant, LowerPoison, LowerSelect>(
      converter, patterns.getContext(), layouts, runtime);
}

} // namespace idr::conversion
