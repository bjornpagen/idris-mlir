// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The patterns of the ops that call the runtime: each op the table
// generated from the ops' marks pairs with its C function
// (IdrRuntimeAbi.inc, Abi<Op>::entry), which says how the function takes
// the op's operands and gives its result.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Ranges.h"
#include "idr/Conversion/IdrPattern.h"
#include "idr/Conversion/Patterns.h"
#include "idr/Conversion/Runtime.h"
#include "idr/Conversion/Words.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Interfaces/InferIntRangeInterface.h"
#include "mlir/Transforms/DialectConversion.h"

// The runtime's C ABI: the word of a small Integer.
#include "idris_rt.h"

using namespace mlir;

namespace idr::conversion {

namespace {

using idr::runtime::ResultKind;

// The range an op states for its value whatever its operands are: the
// runtime keeps the op's meaning, so what the call gives stands for a
// value in it. An op whose range depends on its operands states nothing
// here, since every operand is taken to be any value.
std::optional<ConstantIntRanges> statedRange(Operation *op) {
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
  return stated;
}

// The range, as LLVM's `range`, of what a function of result `kind` gives
// for a value in `stated`. A word is its value. A big gives its word, which
// is the small word of a value that fits a small and a cell's address for
// any other: only a range of small values says where the words are. LLVM's
// range is half-open, so a range up to the type's largest value is one it
// cannot state, and says nothing worth stating. Any other result states no
// range: a pointer, a bool and a string are no number the op ranges, a
// double is no integer, a wrapped integer and an order are read through the
// op's width and predicate, and no result is none.
std::optional<LLVM::ConstantRangeAttr> givenRange(MLIRContext *ctx, ResultKind kind,
                                                  const ConstantIntRanges &stated) {
  using enum ResultKind;
  switch (kind) {
  case Int32:
  case Int64:
    if (stated.umax().isMaxValue())
      return std::nullopt;
    return LLVM::ConstantRangeAttr::get(ctx, stated.umin(), stated.umax() + 1);
  case Big: {
    ranges::Bounds bounds = ranges::boundsOf(stated);
    if (!bounds.fits())
      return std::nullopt;
    // Modulo 2^64, as LLVM reads a range that wraps: the largest small
    // value's word is the largest i64, and the end after it 2^63.
    uint64_t lower = static_cast<uint64_t>(idris_rt_small_word(*bounds.lo));
    uint64_t upper = static_cast<uint64_t>(idris_rt_small_word(*bounds.hi)) + 1;
    return LLVM::ConstantRangeAttr::get(ctx, APInt(64, lower), APInt(64, upper));
  }
  case Void:
  case NoReturn:
  case Double:
  case Wrapped:
  case Order:
  case Str:
  case Pointer:
  case Bool:
    return std::nullopt;
  }
}

// The op's value from what its function gives, as the function's result
// kind, a constant of the table, says: a wrapped integer is the function's
// 64 bits, which the op wraps to its width; an order is the function's
// three-way comparison, which the op compares with 0 by its predicate (the
// generator gives an i1 the Order kind only beside a predicate, so only an
// op with one reads it); any other is the value itself, in the range the op
// states.
template <typename OpT>
Value resultOf(OpT op, LLVM::CallOp call, Type result, ConversionPatternRewriter &rewriter) {
  constexpr ResultKind kind = idr::runtime::Abi<OpT>::entry.result;
  Location loc = op.getLoc();
  Value given = call.getResult();
  if constexpr (kind == ResultKind::Wrapped) {
    return given.getType() == result ? given
                                     : Value(arith::TruncIOp::create(rewriter, loc, result, given));
  } else if constexpr (kind == ResultKind::Order) {
    Value zero = arith::ConstantIntOp::create(rewriter, loc, 0, 32);
    return arith::CmpIOp::create(rewriter, loc, layout::signedPredicate(op.getPredicate()), given,
                                 zero);
  } else {
    if (std::optional<ConstantIntRanges> stated = statedRange(op))
      if (std::optional<LLVM::ConstantRangeAttr> range =
              givenRange(rewriter.getContext(), kind, *stated))
        call.setResAttrsAttr(rewriter.getArrayAttr(rewriter.getDictionaryAttr(
            rewriter.getNamedAttr(LLVM::LLVMDialect::getRangeAttrName(), *range))));
    return given;
  }
}

// An op's precondition (a divisor that is not zero, an index within the
// string) is its guard's, tested before the op: the call is all the op
// lowers to. The op's results are the world, which converts to no value,
// and at most one value, the function's: the table gives the op a function
// of no result exactly when it has no other.
template <typename OpT>
struct LowerRuntimeCall : IdrPattern<OpT> {
  using IdrPattern<OpT>::IdrPattern;
  LogicalResult matchAndRewrite(OpT op, typename IdrPattern<OpT>::OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    LLVM::CallOp call =
        this->runtime.call(rewriter, op, idr::runtime::Abi<OpT>::entry, adaptor.getOperands());
    SmallVector<SmallVector<Value>> out;
    for (Type type : op->getResultTypes()) {
      SmallVector<Type> converted;
      if (failed(this->getTypeConverter()->convertType(type, converted)))
        return rewriter.notifyMatchFailure(op, "a result's type does not convert");
      // The world converts to nothing; the value, to the one C value.
      if (converted.empty())
        out.emplace_back();
      else
        out.push_back({resultOf(op, call, converted.front(), rewriter)});
    }
    rewriter.replaceOpWithMultiple(op, std::move(out));
    return success();
  }
};

template <typename... Ops>
void addRuntimeCalls(RewritePatternSet &patterns, const TypeConverter &converter,
                     const Layouts &layouts, Runtime &runtime) {
  auto add = [&]<typename OpT>() {
    if constexpr (requires { idr::runtime::Abi<OpT>::entry; })
      patterns.add<LowerRuntimeCall<OpT>>(converter, patterns.getContext(), layouts, runtime);
  };
  (add.template operator()<Ops>(), ...);
}

} // namespace

// The patterns of the ops that call the runtime: every op the table pairs
// with a function, the big ops among them, whose small case the runtime
// keeps inline.
void populateRuntimeCallPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                                 const Layouts &layouts, Runtime &runtime) {
  addRuntimeCalls<
#define GET_OP_LIST
#include "idr/IR/IdrOps.cpp.inc"
      >(patterns, converter, layouts, runtime);
}

} // namespace idr::conversion
