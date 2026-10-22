// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The patterns of the ops that call the runtime: each op the generated ABI
// table pairs with its C function (Abi<Op>::entry), which says how the
// function takes the op's operands and gives its results. The call says
// what the op's declaration says it does, as LLVM's attributes, since
// linking the runtime replaces a declaration's attributes by the
// definition's.

#include "idr/Conversion/Lower/Lower.h"

#include "idr/IR/Effects/Declared.h"
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
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
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
// cannot state, and says nothing worth stating. A function that returns no
// value states none, and any other result states no range: a pointer, a
// bool and a string are no number the op ranges, a double is no integer,
// and a wrapped integer and an order are read through the op's width and
// predicate.
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

// One value of the op from what its function gives of the kind `kind`: a
// wrapped integer is the function's 64 bits, which the op wraps to its
// width; an order is the function's three-way comparison, which the op
// compares with 0 by its predicate (the specification gives an i1 the
// Order kind only beside a predicate, so only an op with one reads it);
// any other is the value itself.
template <typename OpT>
Value resultOf(OpT op, ResultKind kind, Value given, Type result,
               ConversionPatternRewriter &rewriter) {
  Location loc = op.getLoc();
  if (kind == ResultKind::Wrapped)
    return given.getType() == result ? given
                                     : Value(arith::TruncIOp::create(rewriter, loc, result, given));
  if constexpr (requires { op.getPredicate(); })
    if (kind == ResultKind::Order) {
      Value zero = arith::ConstantIntOp::create(rewriter, loc, 0, 32);
      return arith::CmpIOp::create(rewriter, loc, layout::signedPredicate(op.getPredicate()),
                                   given, zero);
    }
  return given;
}

// What one op does, as its row would hold it: its declaration's effects,
// or every effect for an op that declares none.
template <typename OpT>
effects::Row rowOf(OpT op) {
  if constexpr (effects::HasDeclaration<OpT>)
    return effects::own(op).row();
  else
    return effects::EffectSet::everything().row();
}

// An op whose function is its meaning: the call is all it lowers to, its
// precondition its guard's, tested before it. Its result is what the
// function gives: none, or the one it returns. What the call does is the
// op's declaration's, a constant of its class where its class decides it,
// made once with the pattern.
template <typename OpT>
struct LowerRuntimeCall : IdrPattern<OpT> {
  LowerRuntimeCall(const TypeConverter &converter, MLIRContext *ctx, const Layouts &layouts,
                   Runtime &runtime)
      : IdrPattern<OpT>(converter, ctx, layouts, runtime) {
    if constexpr (effects::DecidedByClass<OpT>)
      classFacts = callFacts(ctx, effects::bound<OpT>().row());
  }

  // What every call of an op of the class does, where its class decides it:
  // made once, here, so no attribute is made where a function is lowered.
  std::optional<CallFacts> classFacts;

  LogicalResult matchAndRewrite(OpT op, typename IdrPattern<OpT>::OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    constexpr const idr::runtime::Function &function = idr::runtime::Abi<OpT>::entry;
    Location loc = op.getLoc();
    MLIRContext *ctx = rewriter.getContext();
    SmallVector<Type> converted;
    for (Type type : op->getResultTypes())
      if (failed(this->getTypeConverter()->convertType(type, converted)))
        return rewriter.notifyMatchFailure(op, "a result's type does not convert");
    LLVM::CallOp call = this->runtime.call(rewriter, op, function, adaptor.getOperands());
    // An op whose types decide what it does says so of itself.
    tellCall(call, classFacts ? *classFacts : callFacts(ctx, rowOf(op)));
    SmallVector<Value> values;
    switch (function.result) {
    case ResultKind::Void:
    case ResultKind::NoReturn:
      break;
    case ResultKind::Int32:
    case ResultKind::Int64:
    case ResultKind::Double:
    case ResultKind::Wrapped:
    case ResultKind::Order:
    case ResultKind::Str:
    case ResultKind::Big:
    case ResultKind::Pointer:
    case ResultKind::Bool: {
      if (std::optional<ConstantIntRanges> stated = statedRange(op))
        if (std::optional<LLVM::ConstantRangeAttr> range =
                givenRange(ctx, function.result, *stated))
          call.setResAttrsAttr(rewriter.getArrayAttr(rewriter.getDictionaryAttr(
              rewriter.getNamedAttr(LLVM::LLVMDialect::getRangeAttrName(), *range))));
      values.push_back(
          resultOf(op, function.result, call.getResult(), converted.front(), rewriter));
      break;
    }
    }
    // A terminator whose function never returns ends its block where the
    // call does.
    if (op->template hasTrait<mlir::OpTrait::IsTerminator>()) {
      rewriter.replaceOpWithNewOp<ub::UnreachableOp>(op);
      return success();
    }
    SmallVector<SmallVector<Value>> results;
    for (Value value : values)
      results.push_back({value});
    rewriter.replaceOpWithMultiple(op, std::move(results));
    return success();
  }
};

// An exit with a status no parent can read, outside 0 to 255, is a crash at
// the exit's site, which only the site knows to name: the test is there,
// the one test of a status, and a constant status folds it. Every other
// status ends the run by the exit's own function, which takes the byte a
// parent reads: past the test the status fits one, so its truncation drops
// no set bit, and says so.
struct LowerExit : IdrPattern<IoExitOp> {
  LowerExit(const TypeConverter &converter, MLIRContext *ctx, const Layouts &layouts,
            Runtime &runtime)
      : IdrPattern(converter, ctx, layouts, runtime, ownLowering) {}

  LogicalResult matchAndRewrite(IoExitOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    Value status = adaptor.getStatus().front();
    Value unreportable =
        arith::CmpIOp::create(rewriter, loc, arith::CmpIPredicate::ugt, status,
                              arith::ConstantIntOp::create(rewriter, loc, 255, 64));
    auto check = scf::IfOp::create(rewriter, loc, unreportable, /*withElseRegion=*/false);
    {
      OpBuilder::InsertionGuard guard(rewriter);
      rewriter.setInsertionPointToStart(check.thenBlock());
      SmallVector<Value> args{status};
      llvm::append_range(args, runtime.siteOperands(rewriter, loc, op.getSite()));
      runtime.call(rewriter, loc, idr::runtime::helper::unreportableAt, args).setCold(true);
    }
    Value byte = arith::TruncIOp::create(rewriter, loc, rewriter.getI8Type(), status,
                                         arith::IntegerOverflowFlags::nuw);
    runtime.call(rewriter, loc, idr::runtime::Abi<IoExitOp>::entry, byte);
    rewriter.replaceOpWithNewOp<ub::UnreachableOp>(op);
    return success();
  }
};

// An op the table gives a function of its own.
template <typename OpT>
concept CallsRuntime = requires { idr::runtime::Abi<OpT>::entry; };

template <typename... Ops>
void addRuntimeCalls(RewritePatternSet &patterns, const TypeConverter &converter,
                     const Layouts &layouts, Runtime &runtime) {
  auto add = [&]<typename OpT>() {
    if constexpr (CallsRuntime<OpT>)
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
  patterns.add<LowerExit>(converter, patterns.getContext(), layouts, runtime);
}

} // namespace idr::conversion
