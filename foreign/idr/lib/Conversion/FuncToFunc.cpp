// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Phase 0 of idr-lower: idr.func, idr.call and idr.return become func.func,
// func.call and func.return under the mangled names. What LLVM learns of a
// function's values was read before this; its other facts were for the
// passes that are over, and go with the op.

#include "idr/IR/IdrDialect.h"
#include "idr/Conversion/FuncToFunc.h"
#include "idr/Conversion/Mangle.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/PatternMatch.h"

using namespace mlir;

namespace idr::conversion {

namespace {

struct FuncToFunc : OpRewritePattern<idr::FuncOp> {
  FuncToFunc(MLIRContext *ctx, SymbolTable &symbols) : OpRewritePattern(ctx), symbols(symbols) {}

  LogicalResult matchAndRewrite(idr::FuncOp op, PatternRewriter &rewriter) const override {
    std::string name = mangle(op.getSymName());
    // The mangling is injective, and a symbol the frontend or a pass names
    // never holds a code point's escape, so the name is the function's own;
    // the table would rename a function that met another symbol there.
    if (Operation *other = symbols.lookup(name); other && other != op)
      return op.emitError() << "internal error: idr-lower: the function @" << op.getSymName()
                            << " mangles to @" << name << ", which names another symbol";
    symbols.remove(op);
    rewriter.setInsertionPoint(op);
    auto fn = func::FuncOp::create(rewriter, op.getLoc(), name, op.getFunctionType());
    fn.setSymVisibilityAttr(op.getSymVisibilityAttr());
    rewriter.inlineRegionBefore(op.getBody(), fn.getBody(), fn.getBody().end());
    rewriter.eraseOp(op);
    symbols.insert(fn);
    return success();
  }

  SymbolTable &symbols;
};

struct CallToCall : OpRewritePattern<idr::CallOp> {
  using OpRewritePattern::OpRewritePattern;
  LogicalResult matchAndRewrite(idr::CallOp op, PatternRewriter &rewriter) const override {
    rewriter.replaceOpWithNewOp<func::CallOp>(op, mangle(op.getCallee()), op.getResultTypes(),
                                              op.getArgs());
    return success();
  }
};

struct ReturnToReturn : OpRewritePattern<idr::ReturnOp> {
  using OpRewritePattern::OpRewritePattern;
  LogicalResult matchAndRewrite(idr::ReturnOp op, PatternRewriter &rewriter) const override {
    rewriter.replaceOpWithNewOp<func::ReturnOp>(op, op->getOperands());
    return success();
  }
};

} // namespace

void populateFuncToFuncPatterns(RewritePatternSet &patterns, SymbolTable &symbols) {
  patterns.add<FuncToFunc>(patterns.getContext(), symbols);
  patterns.add<CallToCall, ReturnToReturn>(patterns.getContext());
}

} // namespace idr::conversion
