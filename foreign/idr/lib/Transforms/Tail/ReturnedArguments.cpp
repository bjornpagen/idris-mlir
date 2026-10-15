// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
//===- ReturnedArguments.cpp - idr-returned-arguments ---------------------===//
//
// A result that a function always returns as one of its arguments is
// dropped, and its callers use the argument instead. Dropping it shrinks
// every such function's result, which the target returns through memory
// once it has more components than registers.
//
// Which results drop is a question about every function at once, so the
// module pass answers it (Returned); the rewrite is per function and runs
// nested: each function sets its own type and returns, and rewrites the
// calls in its own body of functions whose results drop, reading only the
// answer, so no function reads a sibling while that sibling changes.
//
//===----------------------------------------------------------------------===//

#include "idr/Transforms/Tail.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Rewrite/FrozenRewritePatternSet.h"
#include "mlir/Transforms/WalkPatternRewriteDriver.h"
#include "llvm/ADT/BitVector.h"

namespace idr {
#define GEN_PASS_DEF_IDRRETURNEDARGUMENTS
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::tail {
namespace {

using Known = Returned::Known;

// `attrs`, one per result or none, at the positions `kept`.
ArrayAttr keep(ArrayAttr attrs, ArrayRef<unsigned> kept) {
  if (!attrs)
    return attrs;
  SmallVector<Attribute> out;
  for (unsigned i : kept)
    out.push_back(attrs[i]);
  return ArrayAttr::get(attrs.getContext(), out);
}

// A call of a function whose results drop: the call has the kept results,
// and each dropped one is the operand the call passed in its place.
struct DropFromCall : OpRewritePattern<func::CallOp> {
  DropFromCall(MLIRContext *ctx, const Returned &returned) : OpRewritePattern(ctx), returned(returned) {}

  LogicalResult matchAndRewrite(func::CallOp call, PatternRewriter &rewriter) const override {
    const Returned::Function *callee = returned.dropping(call.getCalleeAttr().getAttr());
    if (!callee)
      return failure();
    SmallVector<unsigned> kept = callee->kept();
    SmallVector<Type> types;
    for (unsigned i : kept)
      types.push_back(callee->results[i].type);
    auto fresh = func::CallOp::create(rewriter, call.getLoc(), types, call.getCalleeAttr(), call.getOperands(),
                                      call.getArgAttrsAttr(), keep(call.getResAttrsAttr(), kept),
                                      call.getNoInlineAttr());
    fresh->setDiscardableAttrs(call->getDiscardableAttrDictionary());
    SmallVector<Value> replacements;
    unsigned next = 0;
    for (const Returned::Result &result : callee->results) {
      std::optional<unsigned> argument = result.known.argument();
      replacements.push_back(argument ? call.getOperand(*argument) : fresh.getResult(next++));
    }
    rewriter.replaceOp(call, replacements);
    return success();
  }

  const Returned &returned;
};

// A return of a function whose results drop: it returns the kept ones.
struct DropFromReturn : OpRewritePattern<func::ReturnOp> {
  DropFromReturn(MLIRContext *ctx, const Returned::Function &function)
      : OpRewritePattern(ctx), kept(function.kept()) {}

  LogicalResult matchAndRewrite(func::ReturnOp ret, PatternRewriter &rewriter) const override {
    SmallVector<Value> operands;
    for (unsigned i : kept)
      operands.push_back(ret.getOperand(i));
    rewriter.modifyOpInPlace(ret, [&] { ret->setOperands(operands); });
    return success();
  }

  SmallVector<unsigned> kept;
};

// The rewrite of one function. It runs only inside idr-returned-arguments,
// which solves Returned on the module right before it and holds it for as
// long as the nested run reads it.
struct DropReturned : PassWrapper<DropReturned, OperationPass<func::FuncOp>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(DropReturned)

  explicit DropReturned(const Returned &returned) : returned(returned) {}

  StringRef getArgument() const final { return "idr-returned-arguments-drop"; }
  StringRef getDescription() const final {
    return "Drop the results Returned found from one function, its returns and its calls";
  }

  void runOnOperation() override {
    func::FuncOp fn = getOperation();
    if (!returned.changes(fn.getSymNameAttr()))
      return markAllAnalysesPreserved();
    MLIRContext *ctx = &getContext();
    RewritePatternSet patterns(ctx);
    patterns.add<DropFromCall>(ctx, returned);
    if (const Returned::Function *own = returned.dropping(fn.getSymNameAttr())) {
      llvm::BitVector dropped(static_cast<unsigned>(own->results.size()));
      for (auto [i, result] : llvm::enumerate(own->results))
        if (result.known.argument())
          dropped.set(static_cast<unsigned>(i));
      (void)fn.eraseResults(dropped);
      patterns.add<DropFromReturn>(ctx, *own);
    }
    walkAndApplyPatterns(fn, FrozenRewritePatternSet(std::move(patterns)));
  }

  const Returned &returned;
};

struct ReturnedArguments : impl::IdrReturnedArgumentsBase<ReturnedArguments> {
  void runOnOperation() override {
    const Returned returned(getOperation());
    if (returned.dropped() == 0)
      return markAllAnalysesPreserved();
    numDropped += returned.dropped();
    OpPassManager nested(ModuleOp::getOperationName());
    nested.addNestedPass<func::FuncOp>(std::make_unique<DropReturned>(returned));
    if (failed(runPipeline(nested, getOperation())))
      return signalPassFailure();
    // No symbol was inserted or erased.
    markAnalysesPreserved<SymbolTable>();
  }
};

} // namespace
} // namespace idr::tail
