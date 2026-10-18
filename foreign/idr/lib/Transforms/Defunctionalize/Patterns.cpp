// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The conversion's patterns for the closures, suspensions, applies, forces,
// constants and signatures, and the generic one that retypes every other
// op. Each takes its operands as the conversion remapped them and moves a
// value into its slot through the converter, so a coercion is made once per
// use that needs it. Another function is read only through the decision's
// signature table, never through its op, which converts on another thread;
// what a constructor of a sum runs is the function it names.

#include "idr/IR/IdrDialect.h"
#include "idr/Analysis/Labels.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Symbols.h"
#include "idr/Support/Remake.h"
#include "idr/Transforms/Defunctionalize.h"

#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/Transforms/DialectConversion.h"

#include "llvm/ADT/STLExtras.h"

#include <cassert>
#include <variant>

using namespace mlir;

namespace idr::defunctionalize {

namespace {

// A closure or a suspension of `label` is its label's constructor in its
// key's sum, its captures moved into the label's parameters and held as the
// constructor's fields.
LogicalResult construct(Operation *op, FlatSymbolRefAttr label, ValueRange captures,
                        const SlotTypeConverter &converter, ConversionPatternRewriter &rewriter) {
  Value made = op->getResult(0);
  Type sum = converter.typeOf(made);
  // A closure or a suspension holds labels, so it has a key.
  Tag tag = converter.slots().labelTag(*converter.keyOf(made), label);
  SmallVector<Value> moved;
  if (failed(converter.coerceOperands(rewriter, op, captures, moved)))
    return failure();
  SmallVector<Value> held;
  for (auto [value, type] : llvm::zip_equal(moved, dataTypeOf(sum).getCtor(tag).fields))
    held.push_back(heldAs(rewriter, op->getLoc(), value, type));
  rewriter.replaceOpWithNewOp<ConOp>(op, sum, tag, held);
  return success();
}

struct ClosurePattern : SlotPattern<ClosureOp> {
  using SlotPattern::SlotPattern;
  LogicalResult matchAndRewrite(ClosureOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    return construct(op, op.getCalleeAttr(), adaptor.getCaptures(), converter(), rewriter);
  }
};

struct SuspendPattern : SlotPattern<SuspendOp> {
  using SlotPattern::SlotPattern;
  LogicalResult matchAndRewrite(SuspendOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    return construct(op, op.getCalleeAttr(), adaptor.getCaptures(), converter(), rewriter);
  }
};

// An evaluated suspension is a cell already forced: its memo sum's Forced
// state, holding the value moved into the forced state's slot.
struct DelayPattern : SlotPattern<DelayOp> {
  using SlotPattern::SlotPattern;
  LogicalResult matchAndRewrite(DelayOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Type sum = converter().typeOf(op.getResult());
    DataType memo = dataTypeOf(sum);
    Tag forced = memo.getForcedTag();
    Value moved = converter().coerceOperand(rewriter, op.getValueMutable(), adaptor.getValue());
    if (!moved)
      return failure();
    Value held = heldAs(rewriter, op.getLoc(), moved, memo.getCtor(forced).fields.front());
    rewriter.replaceOpWithNewOp<ConOp>(op, sum, forced, ValueRange{held});
    return success();
  }
};

// An apply is a match over its callee's sum, each region calling the
// function its constructor names with the captures, then the arguments. A
// sum without a constructor is no value the program has: that apply never
// runs.
struct ApplyPattern : SlotPattern<ApplyOp> {
  using SlotPattern::SlotPattern;
  LogicalResult matchAndRewrite(ApplyOp apply, OpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = apply.getLoc();
    SmallVector<Type> types;
    for (Value own : apply.getResults())
      types.push_back(converter().typeOf(own));
    Value closure = adaptor.getCallee();
    ArrayRef<Ctor> labels = dataTypeOf(closure.getType()).getCtors();
    if (labels.empty()) {
      SmallVector<Value> poison;
      for (Type type : types)
        poison.push_back(ub::PoisonOp::create(rewriter, loc, type));
      rewriter.replaceOp(apply, poison);
      return success();
    }
    // A case per label, and no default.
    auto tags = llvm::to_vector(dataTypeOf(closure.getType()).getTags());
    auto match = MatchOp::create(rewriter, loc, types, closure, ArrayRef<Tag>(tags));
    for (auto [index, label] : llvm::enumerate(labels))
      if (failed(call(apply, adaptor, label, match.getCaseRegion(static_cast<unsigned>(index)),
                      closure, rewriter)))
        return failure();
    rewriter.replaceOp(apply, match.getResults());
    return success();
  }

  // The region of `label`: its captures bound at the scrutinee's grade and
  // held as its function's parameters, each argument moved into its slot,
  // and each result out of the function's into the apply's. Every
  // constructor of a closure sum is a label, by the body's rule.
  LogicalResult call(ApplyOp apply, OpAdaptor adaptor, const Ctor &label, Region &region,
                     Value closure, ConversionPatternRewriter &rewriter) const {
    const Slots &keys = slots();
    Location loc = apply.getLoc();
    FlatSymbolRefAttr fn = std::get<role::Label>(label.role).fn;
    const Signature &sig = keys.signature(fn.getAttr());
    size_t args = apply.getArgs().size();
    // The label fits the callee's carrier, by the verifier of the op that
    // named it and the carriers of the edges it came along, as the label
    // solve found when the label reached this apply.
    assert(sig.type.getNumInputs() >= args && "a label fits the carrier of the callee that holds it");
    unsigned captures = sig.type.getNumInputs() - static_cast<unsigned>(args);
    OpBuilder::InsertionGuard guard(rewriter);
    SmallVector<Type> bound;
    for (Type param : label.fields)
      bound.push_back(fieldType(closure.getType(), param));
    Block *block = rewriter.createBlock(&region, region.end(), bound,
                                        SmallVector<Location>(bound.size(), loc));
    SmallVector<Value> operands;
    for (auto [capture, param] : llvm::zip_equal(block->getArguments(), label.fields))
      operands.push_back(heldAs(rewriter, loc, capture, param));
    for (auto [i, arg] : llvm::enumerate(apply.getArgs())) {
      Value value = adaptor.getArgs()[i];
      if (carriesLabels(arg.getType())) {
        const Slot &to = sig.arguments[captures + i];
        value = converter().coerce(rewriter, loc, value, converter().keyOf(arg), to,
                                   keys.typeOf(arg.getType(), to));
        if (!value)
          return failure();
      }
      operands.push_back(value);
    }
    auto made = CallOp::create(rewriter, loc, sig.converted.getResults(), fn, operands,
                               /*arg_attrs=*/nullptr, /*res_attrs=*/nullptr);
    SmallVector<Value> yields;
    for (auto [j, own] : llvm::enumerate(apply.getResults())) {
      Value value = made.getResult(static_cast<unsigned>(j));
      if (carriesLabels(own.getType())) {
        value = converter().coerce(rewriter, loc, value, sig.results[j], converter().keyOf(own),
                                   converter().typeOf(own));
        if (!value)
          return failure();
      }
      yields.push_back(value);
    }
    YieldOp::create(rewriter, loc, yields);
    return success();
  }
};

// A force is a call of its cell's dispatch function, the cell taken at the
// function's grade, and the value moved out of the forced state's slot
// into the force's.
struct ForcePattern : SlotPattern<ForceOp> {
  using SlotPattern::SlotPattern;
  LogicalResult matchAndRewrite(ForceOp force, OpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = force.getLoc();
    FlatSymbolRefAttr dispatch = slots().forceOf(*converter().keyOf(force.getSuspension()));
    const Signature &sig = slots().signature(dispatch.getAttr());
    Value cell = heldAs(rewriter, loc, adaptor.getSuspension(), sig.converted.getInput(0));
    auto made = CallOp::create(rewriter, loc, sig.converted.getResults(), dispatch,
                               ValueRange{cell}, /*arg_attrs=*/nullptr, /*res_attrs=*/nullptr);
    Value value = made.getResult(0);
    Value own = force.getResult();
    Type forced = cast<LazyType>(unrestricted(force.getSuspension().getType())).getValue();
    if (carriesLabels(forced)) {
      Slot to = converter().keyOf(own);
      value = converter().coerce(rewriter, loc, value, sig.results.front(), to,
                                 slots().typeOf(forced, to));
      if (!value)
        return failure();
    }
    rewriter.replaceOp(force, heldAs(rewriter, loc, value, converter().typeOf(own)));
    return success();
  }
};

// A constant as the decision converted it, at its slot's type.
struct ConstantPattern : SlotPattern<ConstantOp> {
  using SlotPattern::SlotPattern;
  LogicalResult matchAndRewrite(ConstantOp constant, OpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Attribute value = slots().constantOf(constant);
    if (!value)
      return failure();
    rewriter.replaceOpWithNewOp<ConstantOp>(constant, converter().typeOf(constant.getResult()),
                                            value);
    return success();
  }
};

// A function's signature is its slots': each parameter's and result's type
// from the decision, by the function's name, since a result's key is the
// function's and not its type's. The body's block arguments convert with
// it, the entry block's by the signature.
struct FuncSignaturePattern : SlotPattern<FuncOp> {
  using SlotPattern::SlotPattern;
  LogicalResult matchAndRewrite(FuncOp fn, OpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    FunctionType type = slots().signature(fn.getSymNameAttr()).converted;
    TypeConverter::SignatureConversion signature(type.getNumInputs());
    for (auto [i, input] : llvm::enumerate(type.getInputs()))
      signature.addInputs(static_cast<unsigned>(i), input);
    if (failed(rewriter.convertRegionTypes(&fn.getBody(), converter(), &signature)))
      return failure();
    rewriter.modifyOpInPlace(fn, [&] { fn.setFunctionType(type); });
    return success();
  }
};

// Any other op is made again with its operands moved into their slots, its
// results and region arguments of their plan's types, and its regions moved
// into the new op: a yield, a con, a field, a match, a linear entry or use,
// a poison, an array op, a branch.
struct RetypePattern : ConversionPattern {
  RetypePattern(const SlotTypeConverter &converter, MLIRContext *ctx)
      : ConversionPattern(converter, MatchAnyOpTypeTag(), /*benefit=*/1, ctx) {}

  LogicalResult matchAndRewrite(Operation *op, ArrayRef<Value> operands,
                                ConversionPatternRewriter &rewriter) const override {
    if (isa<FuncOp, CallOp, ReturnOp, ClosureOp, SuspendOp, DelayOp, ApplyOp, ForceOp,
            ConstantOp>(op))
      return failure();
    const auto &converter = *getTypeConverter<SlotTypeConverter>();
    SmallVector<Value> moved;
    if (failed(converter.coerceOperands(rewriter, op, operands, moved)))
      return failure();
    SmallVector<Type> types = llvm::map_to_vector(
        op->getResults(), [&](Value result) { return converter.typeOf(result); });
    Operation *made = remakeOp(rewriter, op, moved, types);
    for (Region &region : made->getRegions())
      if (failed(rewriter.convertRegionTypes(&region, converter)))
        return failure();
    rewriter.replaceOp(op, made->getResults());
    return success();
  }
};

} // namespace

void populateDefunctionalizePatterns(RewritePatternSet &patterns,
                                     const SlotTypeConverter &converter) {
  patterns.add<ClosurePattern, SuspendPattern, DelayPattern, ApplyPattern, ForcePattern,
               ConstantPattern, FuncSignaturePattern, RetypePattern>(converter,
                                                                    patterns.getContext());
}

} // namespace idr::defunctionalize
