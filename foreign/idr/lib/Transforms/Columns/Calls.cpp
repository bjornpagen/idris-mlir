// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The patterns of idr-columns for what carries an array of records from one
// function or region to another: a signature and its entry block, a call,
// a return, and a match's results and the yields that give them. Each array
// moves as its columns.

#include "idr/Transforms/Columns.h"

using namespace mlir;

namespace idr::columns {

namespace {

// Each attribute dictionary of `attrs` once per value its position became.
ArrayAttr expand(ArrayAttr attrs, ArrayRef<unsigned> counts) {
  if (!attrs)
    return attrs;
  SmallVector<Attribute> out;
  for (auto [attr, count] : llvm::zip_equal(attrs, counts))
    out.append(count, attr);
  return ArrayAttr::get(attrs.getContext(), out);
}

//===----------------------------------------------------------------------===//
// Functions, calls and returns
//===----------------------------------------------------------------------===//

struct FuncColumns : OpConversionPattern<FuncOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(FuncOp fn, OneToNOpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    FunctionType type = fn.getFunctionType();
    SmallVector<Type> inputs, results;
    SmallVector<unsigned> inputCounts, resultCounts;
    if (failed(convertEach(*getTypeConverter(), type.getInputs(), inputs, inputCounts)) ||
        failed(convertEach(*getTypeConverter(), type.getResults(), results, resultCounts)))
      return failure();
    TypeConverter::SignatureConversion entry(type.getNumInputs());
    ArrayRef<Type> rest = inputs;
    for (auto [at, count] : llvm::enumerate(inputCounts)) {
      entry.addInputs(static_cast<unsigned>(at), rest.take_front(count));
      rest = rest.drop_front(count);
    }
    if (failed(rewriter.convertRegionTypes(&fn.getBody(), *getTypeConverter(), &entry)))
      return failure();
    rewriter.modifyOpInPlace(fn, [&] {
      fn.setFunctionTypeAttr(TypeAttr::get(FunctionType::get(getContext(), inputs, results)));
      if (ArrayAttr attrs = fn.getArgAttrsAttr())
        fn.setArgAttrsAttr(expand(attrs, inputCounts));
      if (ArrayAttr attrs = fn.getResAttrsAttr())
        fn.setResAttrsAttr(expand(attrs, resultCounts));
    });
    return success();
  }
};

struct CallColumns : OpConversionPattern<CallOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(CallOp call, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    SmallVector<Type> results;
    SmallVector<unsigned> counts;
    if (failed(convertEach(*getTypeConverter(), call->getResultTypes(), results, counts)))
      return failure();
    SmallVector<unsigned> argCounts = llvm::map_to_vector(
        adaptor.getArgs(), [](ValueRange arg) { return static_cast<unsigned>(arg.size()); });
    auto made = cast<CallOp>(
        remakeOp(rewriter, call, flatten(adaptor.getOperands()), results));
    rewriter.modifyOpInPlace(made, [&] {
      if (ArrayAttr attrs = made.getArgAttrsAttr())
        made.setArgAttrsAttr(expand(attrs, argCounts));
      if (ArrayAttr attrs = made.getResAttrsAttr())
        made.setResAttrsAttr(expand(attrs, counts));
    });
    SmallVector<SmallVector<Value>> replaced = runs(made->getResults(), counts);
    rewriter.replaceOpWithMultiple(call, replaced);
    return success();
  }
};

// A terminator whose every operand moves on: each array of records moves
// on as its columns.
template <typename OpT>
struct TerminatorColumns : OpConversionPattern<OpT> {
  using OpConversionPattern<OpT>::OpConversionPattern;
  LogicalResult matchAndRewrite(OpT op, typename OpConversionPattern<OpT>::OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    SmallVector<Value> operands = flatten(adaptor.getOperands());
    rewriter.modifyOpInPlace(op, [&] { op->setOperands(operands); });
    return success();
  }
};

} // namespace

// A match gives each array of records its regions yield as the columns
// they yield (ResultColumns). A match's regions bind the fields of its
// constructors, which a data type holds whole, so only what it gives is
// converted. A function is legal once its signature and its body are.
void populateCallColumnPatterns(const TypeConverter &converter, RewritePatternSet &patterns,
                                ConversionTarget &target) {
  ConversionTarget::DynamicLegalityCallbackFn legal = whole(converter);
  addColumns<FuncColumns, FuncOp>(converter, patterns, target,
                                  [&converter](Operation *op) -> std::optional<bool> {
                                    auto fn = cast<FuncOp>(op);
                                    return converter.isSignatureLegal(fn.getFunctionType()) &&
                                           converter.isLegal(&fn.getBody());
                                  });
  addColumns<CallColumns, CallOp>(converter, patterns, target, legal);
  addColumns<TerminatorColumns<ReturnOp>, ReturnOp>(converter, patterns, target, legal);
  addColumns<TerminatorColumns<YieldOp>, YieldOp>(converter, patterns, target, legal);
  addColumns<ResultColumns<MatchOp>, MatchOp>(converter, patterns, target, legal);
  addColumns<ResultColumns<MatchLitOp>, MatchLitOp>(converter, patterns, target, legal);
}

} // namespace idr::columns
