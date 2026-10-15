// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The patterns of the ops that call the runtime: each op the table
// generated from the ops' marks pairs with its C functions
// (IdrRuntimeAbi.inc), which says how each function takes the op's
// operands and gives its result.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Layout.h"
#include "idr/Conversion/IdrPattern.h"
#include "idr/Conversion/Patterns.h"
#include "idr/Conversion/Runtime.h"
#include "idr/Conversion/Words.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Interfaces/InferIntRangeInterface.h"
#include "mlir/Transforms/DialectConversion.h"

using namespace mlir;

namespace idr::conversion {

namespace {

// The range an op states for its result whatever its operands are, as
// LLVM's `range`: the runtime keeps the op's meaning, so the call's result
// is in it too. An op whose range depends on its operands states nothing
// here, since every operand is taken to be any value.
std::optional<LLVM::ConstantRangeAttr> statedRange(Operation *op) {
  auto ranged = dyn_cast<InferIntRangeInterface>(op);
  if (!ranged || op->getNumResults() != 1)
    return std::nullopt;
  auto operands = llvm::map_to_vector(op->getOperands(), [](Value operand) {
    return IntegerValueRange::getMaxRange(operand);
  });
  std::optional<ConstantIntRanges> stated;
  ranged.inferResultRangesFromOptional(operands, [&](Value, const IntegerValueRange &range) {
    if (!range.isUninitialized())
      stated = range.getValue();
  });
  // LLVM's range is half-open, so a range up to the type's largest value
  // is one LLVM cannot state, and says nothing worth stating.
  if (!stated || stated->umax().isMaxValue())
    return std::nullopt;
  return LLVM::ConstantRangeAttr::get(op->getContext(), stated->umin(), stated->umax() + 1);
}

// The op's value from what its function gives. A wrapped integer is the
// function's 64 bits, which the op wraps to its width; an order is the
// function's three-way comparison, which the op compares with 0 by its
// predicate; any other is the value itself, in the range the op states.
template <typename OpT>
Value resultOf(OpT op, const idr::runtime::Function &function, Value given, Type result,
               ConversionPatternRewriter &rewriter) {
  using idr::runtime::Kind;
  Location loc = op.getLoc();
  if (function.result == Kind::Wrapped)
    return given.getType() == result ? given
                                     : Value(arith::TruncIOp::create(rewriter, loc, result, given));
  if (function.result == Kind::Order) {
    if constexpr (requires { op.getPredicate(); }) {
      Value zero = arith::ConstantIntOp::create(rewriter, loc, 0, 32);
      return arith::CmpIOp::create(rewriter, loc, layout::signedPredicate(op.getPredicate()),
                                   given, zero);
    }
  }
  if (std::optional<LLVM::ConstantRangeAttr> range = statedRange(op))
    given.getDefiningOp<LLVM::CallOp>().setResAttrsAttr(rewriter.getArrayAttr(
        rewriter.getDictionaryAttr(rewriter.getNamedAttr(LLVM::LLVMDialect::getRangeAttrName(),
                                                         *range))));
  return given;
}

// An op's precondition (a divisor that is not zero, an index within the
// string) is its guard's, tested before the op: the call is all the op
// lowers to. The op's results are the world, which is nothing, and at most
// one value, the function's.
template <typename OpT>
struct LowerRuntimeCall : IdrPattern<OpT> {
  using IdrPattern<OpT>::IdrPattern;
  LogicalResult matchAndRewrite(OpT op, typename IdrPattern<OpT>::OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    const idr::runtime::Function &function = runtimeFunctionOf(op);
    Value given = this->runtime.call(rewriter, op, function, adaptor.getOperands());
    SmallVector<SmallVector<Value>> out;
    for (Type type : op->getResultTypes()) {
      SmallVector<Type> components = this->layouts.components(type);
      if (components.empty())
        out.emplace_back();
      else
        out.push_back({resultOf(op, function, given, components.front(), rewriter)});
    }
    rewriter.replaceOpWithMultiple(op, std::move(out));
    return success();
  }
};

template <typename... Ops>
void addRuntimeCalls(RewritePatternSet &patterns, const TypeConverter &converter,
                     const Layouts &layouts, Runtime &runtime) {
  auto add = [&]<typename OpT>() {
    if constexpr (requires { idr::runtime::Abi<OpT>::functions; })
      patterns.add<LowerRuntimeCall<OpT>>(converter, patterns.getContext(), layouts, runtime);
  };
  (add.template operator()<Ops>(), ...);
}

} // namespace

// The patterns of the ops that call the runtime: every op the table pairs
// with a function. A big op whose small case is inline has a pattern of its
// own, ahead of this one.
void populateRuntimeCallPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                                 const Layouts &layouts, Runtime &runtime) {
  addRuntimeCalls<
#define GET_OP_LIST
#include "idr/IR/IdrOps.cpp.inc"
      >(patterns, converter, layouts, runtime);
}

} // namespace idr::conversion
