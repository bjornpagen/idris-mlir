// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The patterns of the ops that call the runtime: each op the table
// generated from the ops' marks pairs with its C functions
// (IdrRuntimeAbi.inc), which says how each function takes the op's
// operands and gives its result.

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
#include "llvm/Support/ErrorHandling.h"

using namespace mlir;

namespace idr::conversion {

namespace {

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
// is 2v+1 for a value v that fits a small and a cell's address for any
// other: only a range of small values says where the words are. LLVM's
// range is half-open, so a range up to the type's largest value is one it
// cannot state, and says nothing worth stating.
std::optional<LLVM::ConstantRangeAttr> givenRange(MLIRContext *ctx, idr::runtime::Kind kind,
                                                  const ConstantIntRanges &stated) {
  using idr::runtime::Kind;
  switch (kind) {
  case Kind::Int32:
  case Kind::Int64:
    if (stated.umax().isMaxValue())
      return std::nullopt;
    return LLVM::ConstantRangeAttr::get(ctx, stated.umin(), stated.umax() + 1);
  case Kind::Big: {
    ranges::Bounds bounds = ranges::boundsOf(stated);
    if (!bounds.fits())
      return std::nullopt;
    // Modulo 2^64, as LLVM reads a range that wraps: the largest small
    // value's word is the largest i64, and the end after it 2^63.
    uint64_t lower = static_cast<uint64_t>(*bounds.lo) * 2 + 1;
    uint64_t upper = static_cast<uint64_t>(*bounds.hi) * 2 + 2;
    return LLVM::ConstantRangeAttr::get(ctx, APInt(64, lower), APInt(64, upper));
  }
  case Kind::World:
  case Kind::Double:
  case Kind::Signed:
  case Kind::Unsigned:
  case Kind::Wrapped:
  case Kind::Order:
  case Kind::Str:
  case Kind::Buffer:
  case Kind::Void:
    return std::nullopt;
  }
  llvm_unreachable("a runtime function's result is one of the table's kinds");
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
  if (std::optional<ConstantIntRanges> stated = statedRange(op))
    if (std::optional<LLVM::ConstantRangeAttr> range =
            givenRange(rewriter.getContext(), function.result, *stated))
      given.getDefiningOp<LLVM::CallOp>().setResAttrsAttr(rewriter.getArrayAttr(
          rewriter.getDictionaryAttr(rewriter.getNamedAttr(LLVM::LLVMDialect::getRangeAttrName(),
                                                           *range))));
  return given;
}

// An op's precondition (a divisor that is not zero, an index within the
// string) is its guard's, tested before the op: the call is all the op
// lowers to. The op's results are the world, which is nothing, and at most
// one value, the function's: the table gives the op a function of a Void
// result exactly when it has no other.
template <typename OpT>
struct LowerRuntimeCall : IdrPattern<OpT> {
  using IdrPattern<OpT>::IdrPattern;
  LogicalResult matchAndRewrite(OpT op, typename IdrPattern<OpT>::OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    const idr::runtime::Function &function = runtimeFunctionOf(op);
    std::optional<Value> given =
        this->runtime.call(rewriter, op, function, adaptor.getOperands());
    SmallVector<SmallVector<Value>> out;
    for (Type type : op->getResultTypes()) {
      SmallVector<Type> components = this->layouts.components(type);
      if (components.empty())
        out.emplace_back();
      else
        out.push_back({resultOf(op, function, *given, components.front(), rewriter)});
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
