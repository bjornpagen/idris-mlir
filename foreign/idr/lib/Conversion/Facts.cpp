// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What idr-lower tells LLVM about the values functions take and return:
// written by the signature conversion itself, which knows where each
// parameter's components go, as upstream's FuncToLLVM moves argument
// attributes across a signature it splits.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Layout.h"
#include "idr/Conversion/Facts.h"
#include "idr/Conversion/Words.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/LLVMIR/LLVMAttrs.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/Builders.h"
#include "llvm/ADT/STLExtras.h"

#include <optional>

// The runtime's C ABI: a cell starts with its header.
#include "idris_rt.h"

using namespace mlir;

namespace idr::conversion {

namespace {

// The attributes of a pointer to a cell. Static data and live cells alike
// are aligned to a cell's start and start with their header.
SmallVector<NamedAttribute> cellFacts(Builder &b) {
  return {b.getNamedAttr(LLVM::LLVMDialect::getNonNullAttrName(), b.getUnitAttr()),
          b.getNamedAttr(LLVM::LLVMDialect::getAlignAttrName(),
                         b.getI64IntegerAttr(cellAlignment())),
          b.getNamedAttr(LLVM::LLVMDialect::getDereferenceableAttrName(),
                         b.getI64IntegerAttr(static_cast<int64_t>(sizeof(idris_rt_header))))};
}

// The facts of the first component of a value of `type`: a cell's pointer,
// and an unboxed sum's tag, which is below its number of constructors. No
// other component has any.
SmallVector<NamedAttribute> componentFacts(Type type, const Layouts &layouts, Builder &b) {
  if (isCellPointer(type))
    return cellFacts(b);
  auto data = dyn_cast<DataType>(unrestricted(type));
  if (!data)
    return {};
  std::optional<IntegerType> tag = layouts.sum(data).tag;
  if (!tag)
    return {};
  unsigned width = tag->getWidth();
  uint64_t count = data.getCtors().size();
  // A tag type that the constructors fill has no range to state.
  if (count >= (uint64_t{1} << width))
    return {};
  return {b.getNamedAttr(
      LLVM::LLVMDialect::getRangeAttrName(),
      LLVM::ConstantRangeAttr::get(b.getContext(), width, 0, static_cast<int64_t>(count)))};
}

// What upstream's signature conversion of a function op does for a body of
// one block, the facts written where the conversion maps each parameter.
struct LowerSignature : OpConversionPattern<func::FuncOp> {
  LowerSignature(const TypeConverter &converter, MLIRContext *ctx, const Layouts &layouts)
      : OpConversionPattern(converter, ctx), layouts(layouts) {}

  LogicalResult matchAndRewrite(func::FuncOp fn, OpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    const TypeConverter &converter = *getTypeConverter();
    FunctionType type = fn.getFunctionType();
    TypeConverter::SignatureConversion signature(type.getNumInputs());
    SmallVector<Type> results;
    if (failed(converter.convertSignatureArgs(type.getInputs(), signature)) ||
        failed(converter.convertTypes(type.getResults(), results)))
      return failure();
    rewriter.modifyOpInPlace(fn, [&] {
      fn.setFunctionType(FunctionType::get(getContext(), signature.getConvertedTypes(), results));
      // A parameter of no component (the world) has no mapping, and so no
      // facts.
      for (auto [index, input] : llvm::enumerate(type.getInputs()))
        if (std::optional<TypeConverter::SignatureConversion::InputMapping> mapping =
                signature.getInputMapping(static_cast<unsigned>(index)))
          for (const NamedAttribute &fact : componentFacts(input, layouts, rewriter))
            fn.setArgAttr(static_cast<unsigned>(mapping->inputNo), fact.getName(),
                          fact.getValue());
      // A result of several components becomes one struct in LLVM, which
      // takes no such facts; a cell pointer is one component.
      if (type.getNumResults() == 1 && isCellPointer(type.getResult(0)))
        for (const NamedAttribute &fact : cellFacts(rewriter))
          fn.setResultAttr(0, fact.getName(), fact.getValue());
    });
    rewriter.applySignatureConversion(&fn.getBody().front(), signature, &converter);
    return success();
  }

  const Layouts &layouts;
};

} // namespace

void populateSignaturePatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                               const Layouts &layouts) {
  patterns.add<LowerSignature>(converter, patterns.getContext(), layouts);
}

} // namespace idr::conversion
