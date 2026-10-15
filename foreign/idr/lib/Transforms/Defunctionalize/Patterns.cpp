// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The conversion's patterns for the closures, suspensions, applies, forces,
// constants and signatures, and the generic one that retypes every other
// op. Each takes its operands as the conversion remapped them and moves a
// value into its slot through the converter, so a coercion is made once per
// use that needs it. Another function is read only through the decision's
// signature table, never through its op, which converts on another thread.

#include "idr/IR/IdrDialect.h"
#include "idr/Analysis/Labels.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Symbols.h"
#include "idr/Transforms/Defunctionalize.h"

#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/OperationSupport.h"
#include "mlir/Transforms/DialectConversion.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::defunctionalize {

namespace {

// The field types of the constructor named `name` of the sum a value of
// `sum` is: a label's captures, or a memo state's value.
ArrayRef<Type> fieldsOf(Type sum, StringRef name) {
  DataType data = dataTypeOf(sum);
  std::optional<unsigned> tag = data.getTag(name);
  assert(tag && "every label of a key has its constructor in the key's sum");
  return data.getCtor(*tag).fields;
}

// A closure or a suspension of `label` is its label's constructor in its
// key's sum, its captures moved into the label's parameters and held as the
// constructor's fields.
LogicalResult construct(Operation *op, FlatSymbolRefAttr label, ValueRange captures,
                        const SlotTypeConverter &converter, ConversionPatternRewriter &rewriter) {
  Type sum = converter.typeOf(op->getResult(0));
  SmallVector<Value> moved;
  if (failed(converter.coerceOperands(rewriter, op, captures, moved)))
    return failure();
  SmallVector<Value> held;
  for (auto [value, type] : llvm::zip_equal(moved, fieldsOf(sum, label.getValue())))
    held.push_back(heldAs(rewriter, op->getLoc(), value, type));
  rewriter.replaceOpWithNewOp<ConOp>(op, sum, label, held);
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

// An evaluated suspension is a cell already forced: its memo sum's `forced`
// constructor, holding the value moved into the forced state's slot.
struct DelayPattern : SlotPattern<DelayOp> {
  using SlotPattern::SlotPattern;
  LogicalResult matchAndRewrite(DelayOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Type sum = converter().typeOf(op.getResult());
    Value moved = converter().coerceOperand(rewriter, op.getValueMutable(), adaptor.getValue());
    if (!moved)
      return failure();
    Value held = heldAs(rewriter, op.getLoc(), moved, fieldsOf(sum, memoForced).front());
    rewriter.replaceOpWithNewOp<ConOp>(op, sum,
                                       FlatSymbolRefAttr::get(op.getContext(), memoForced),
                                       ValueRange{held});
    return success();
  }
};

// An apply is a match over its callee's sum, each region calling its label
// with the captures, then the arguments. A callee no label reaches is no
// value the program has: that apply never runs.
struct ApplyPattern : SlotPattern<ApplyOp> {
  using SlotPattern::SlotPattern;
  LogicalResult matchAndRewrite(ApplyOp apply, OpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = apply.getLoc();
    Key callee = converter().keyOf(apply.getCallee());
    SmallVector<Type> types;
    for (Value own : apply.getResults())
      types.push_back(converter().typeOf(own));
    if (Slots::isEmpty(callee)) {
      SmallVector<Value> poison;
      for (Type type : types)
        poison.push_back(ub::PoisonOp::create(rewriter, loc, type));
      rewriter.replaceOp(apply, poison);
      return success();
    }
    Value closure = adaptor.getCallee();
    auto match = MatchOp::create(rewriter, loc, types, closure, callee.second,
                                 static_cast<unsigned>(callee.second.size()));
    for (auto [label, region] :
         llvm::zip(callee.second.getAsRange<FlatSymbolRefAttr>(), match.getRegions()))
      if (failed(call(apply, adaptor, label, region, closure, rewriter)))
        return failure();
    rewriter.replaceOp(apply, match.getResults());
    return success();
  }

  // The region of `label`: its captures bound at the scrutinee's grade and
  // held as its parameters, each argument moved into its slot, and each
  // result out of the label's into the apply's.
  LogicalResult call(ApplyOp apply, OpAdaptor adaptor, FlatSymbolRefAttr label, Region &region,
                     Value closure, ConversionPatternRewriter &rewriter) const {
    const Slots &keys = slots();
    Location loc = apply.getLoc();
    const Signature &sig = keys.signature(label.getAttr());
    size_t args = apply.getArgs().size();
    // The label fits the callee's carrier, by the verifier of the op that
    // named it and the carriers of the edges it came along.
    if (sig.type.getNumInputs() < args) {
      apply.emitError("internal error: idr-defunctionalize: ")
          << label << " takes fewer parameters than the apply passes";
      return failure();
    }
    unsigned captures = sig.type.getNumInputs() - static_cast<unsigned>(args);
    OpBuilder::InsertionGuard guard(rewriter);
    ArrayRef<Type> params = fieldsOf(closure.getType(), label.getValue());
    SmallVector<Type> bound;
    for (Type param : params)
      bound.push_back(fieldType(closure.getType(), param));
    Block *block = rewriter.createBlock(&region, region.end(), bound,
                                        SmallVector<Location>(bound.size(), loc));
    SmallVector<Value> operands;
    for (auto [capture, param] : llvm::zip_equal(block->getArguments(), params))
      operands.push_back(heldAs(rewriter, loc, capture, param));
    for (auto [i, arg] : llvm::enumerate(apply.getArgs())) {
      Value value = adaptor.getArgs()[i];
      if (isKeyed(arg.getType())) {
        Key to = sig.arguments[captures + i];
        value = converter().coerce(rewriter, loc, value, converter().keyOf(arg), to,
                                   keys.typeOf(arg.getType(), to));
        if (!value)
          return failure();
      }
      operands.push_back(value);
    }
    auto made = CallOp::create(rewriter, loc, sig.converted.getResults(), label, operands,
                               /*arg_attrs=*/nullptr, /*res_attrs=*/nullptr, /*effects=*/nullptr);
    SmallVector<Value> yields;
    for (auto [j, own] : llvm::enumerate(apply.getResults())) {
      Value value = made.getResult(static_cast<unsigned>(j));
      if (isKeyed(own.getType())) {
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

// A force keeps its op and takes the cell's memo sum; the switch on the
// cell's state is the lowering's.
struct ForcePattern : SlotPattern<ForceOp> {
  using SlotPattern::SlotPattern;
  LogicalResult matchAndRewrite(ForceOp force, OpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOpWithNewOp<ForceOp>(force, converter().typeOf(force.getResult()),
                                         adaptor.getSuspension());
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
    OperationState state(op->getLoc(), op->getName());
    state.addOperands(moved);
    for (Value result : op->getResults())
      state.addTypes(converter.typeOf(result));
    state.addAttributes(op->getDiscardableAttrDictionary().getValue());
    state.propertiesAttr = op->getPropertiesAsAttribute();
    state.addSuccessors(op->getSuccessors());
    for (unsigned i = 0, n = op->getNumRegions(); i < n; ++i)
      state.addRegion();
    Operation *made = rewriter.create(state);
    for (auto [from, into] : llvm::zip(op->getRegions(), made->getRegions())) {
      rewriter.inlineRegionBefore(from, into, into.end());
      if (failed(rewriter.convertRegionTypes(&into, converter)))
        return failure();
    }
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
