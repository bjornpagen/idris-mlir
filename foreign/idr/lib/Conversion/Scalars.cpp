// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The patterns of the crashes (of a cause, of the program's own text), of
// every op whose meaning is one runtime function per case of its kind (a
// clock's reading, a file time's field), and of every op of inline
// arithmetic, whose arith is its meaning over an IR builder
// (Numeric/Trait.h): one pattern for each kind of meaning, so no clock,
// division, shift or char conversion is spelt here.

#include "idr/IR/Effects/Declared.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Numeric/Trait.h"
#include "idr/Conversion/IdrPattern.h"
#include "idr/Conversion/Lower/Lower.h"
#include "idr/Conversion/Patterns.h"
#include "idr/Conversion/Runtime.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/Transforms/DialectConversion.h"

using namespace mlir;

namespace idr::conversion {

namespace {

// A crash of a cause of the closed set at its site, given the operands its
// line reads: the runtime's crash, which does not return, then the end of
// the region, which nothing after it reaches.
struct LowerCrash : IdrPattern<CrashCauseOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(CrashCauseOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    runtime.crash(rewriter, op.getLoc(), op.getCause(), adaptor.getReads(), op.getSite());
    rewriter.replaceOpWithNewOp<ub::UnreachableOp>(op);
    return success();
  }
};

// A trusted library's crash of a string it computed, at its site.
struct LowerCrashMessage : IdrPattern<CrashMessageOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(CrashMessageOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    runtime.crashWith(rewriter, op.getLoc(), adaptor.getMessage(), op.getSite());
    rewriter.replaceOpWithNewOp<ub::UnreachableOp>(op);
    return success();
  }
};

// An op the table gives one function per case of its kind.
template <typename OpT>
concept CallsRuntimeByCase = requires { idr::runtime::AbiByCase<OpT>::entries; };

// The call of the runtime's function of the op's kind, its `kind` property,
// one entry per case in the cases' order (AbiByCase), so the case is
// chosen as the op is lowered and never passed or tested at run time; its
// operands passed as the function takes them. What the call does is the
// op's declaration's, which its class decides, made once with the pattern.
template <CallsRuntimeByCase OpT>
struct LowerByCase : IdrPattern<OpT> {
  static_assert(effects::DecidedByClass<OpT>);
  LowerByCase(const TypeConverter &converter, MLIRContext *ctx, const Layouts &layouts,
              Runtime &runtime)
      : IdrPattern<OpT>(converter, ctx, layouts, runtime),
        facts(callFacts(ctx, effects::bound<OpT>().row())) {}

  CallFacts facts;

  LogicalResult matchAndRewrite(OpT op, typename IdrPattern<OpT>::OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    const idr::runtime::Function &function =
        idr::runtime::AbiByCase<OpT>::entries[static_cast<size_t>(op.getKind())];
    LLVM::CallOp call = this->runtime.call(rewriter, op, function, adaptor.getOperands());
    tellCall(call, facts);
    rewriter.replaceOp(op, call.getResult());
    return success();
  }
};

// An op of inline arithmetic as its meaning over arith.
template <typename OpT>
struct LowerInline : IdrPattern<OpT> {
  using IdrPattern<OpT>::IdrPattern;
  LogicalResult matchAndRewrite(OpT op, typename OpT::Adaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOp(op, OpT::expand(rewriter, op.getLoc(), adaptor.getOperands()));
    return success();
  }
};

// Every op whose meaning is one function per case, by the table, and every
// op whose meaning is inline arithmetic, by its trait: an op the
// specification gives either meaning cannot lack its lowering.
template <typename... Ops>
void addByMeaning(RewritePatternSet &patterns, const TypeConverter &converter,
                  const Layouts &layouts, Runtime &runtime) {
  auto add = [&]<typename OpT>() {
    if constexpr (CallsRuntimeByCase<OpT>)
      patterns.add<LowerByCase<OpT>>(converter, patterns.getContext(), layouts, runtime);
    if constexpr (numeric::InlineOp<OpT>)
      patterns.add<LowerInline<OpT>>(converter, patterns.getContext(), layouts, runtime);
  };
  (add.template operator()<Ops>(), ...);
}

} // namespace

void populateScalarPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                            const Layouts &layouts, Runtime &runtime) {
  patterns.add<LowerCrash, LowerCrashMessage>(converter, patterns.getContext(), layouts, runtime);
  addByMeaning<
#define GET_OP_LIST
#include "idr/IR/IdrOps.cpp.inc"
      >(patterns, converter, layouts, runtime);
}

} // namespace idr::conversion
