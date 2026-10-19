// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Calling a node: the one way a call becomes a call of a specialization or
// raise node, one for each kind. It needs only the node's name: the node's
// function need not exist yet, and what the new call may do is everything
// until its callee is final.
//
// The call passes one operand per parameter the node is built with, though
// no verifier sees the node yet: for a specialization one per hole of its
// key, in the key's order, a leaf of the call or a constant lifted out of
// the key and built at the call at the hole's type, and the node takes one
// parameter per hole in that order, of that type; for a raise the call's
// operands and then the consumer's free values, and the node takes its
// callee's parameters and then the consumer's. Every other call in
// idr-optimize is one the verifier checked on its input, or a clone of one
// that inlining or a build made, so every call passes one argument per
// parameter of its callee.
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Specialize.h"

#include "llvm/ADT/STLExtras.h"

#include <cassert>

using namespace mlir;

namespace idr::specialize::detail {

SmallVector<Value> operandsOf(RewriterBase &rewriter, idr::CallOp call, const SpecWant &want,
                              SpecKeyAttr key, ArrayRef<Source> sources,
                              const Schedule &schedule) {
  // The key's owner is final: the callee, or the owner of the node it is.
  std::optional<FinalCallee> owner = schedule.finalCallee(key.getOrigin());
  assert(owner && "a spec key's owner is a final function of the program");
  SmallVector<Type> types;
  for (auto [pattern, type] : llvm::zip_equal(key.getPatterns(), owner->fn.getArgumentTypes()))
    holeTypes(pattern, type, types);
  rewriter.setInsertionPoint(call);
  SmallVector<Value> operands;
  for (auto [hole, source] : llvm::enumerate(sources))
    operands.push_back(std::visit(
        llvm::makeVisitor([&](Kept kept) { return want.leaves[kept.hole]; },
                          [&](const Lifted &lifted) {
                            // A constant has no hole to take.
                            unsigned none = 0;
                            return rebuild(rewriter, call.getLoc(), lifted.constant, types[hole],
                                           {}, none);
                          }),
        source));
  return operands;
}

// A specialization replaces the call, and returns what the call does.
idr::CallOp redirect(RewriterBase &rewriter, idr::CallOp call, FlatSymbolRefAttr target,
                     ArrayRef<Value> operands) {
  rewriter.setInsertionPoint(call);
  auto fresh = idr::CallOp::create(rewriter, call.getLoc(), call.getResultTypes(), target,
                                   operands, /*arg_attrs=*/ArrayAttr(),
                                   /*res_attrs=*/ArrayAttr());
  SmallVector<Value> old(call.getArgs());
  rewriter.replaceOp(call, fresh.getResults());
  eraseUnused(rewriter, old);
  return fresh;
}

// A raise replaces what the dispatch returns, and returns that; the steps
// from the call's result to the dispatch, each the one use of the one
// before, go from the dispatch back, and the call last.
idr::CallOp redirect(RewriterBase &rewriter, idr::CallOp call, FlatSymbolRefAttr target,
                     const RaiseWant &want) {
  Operation *dispatch = want.consumer.dispatch;
  rewriter.setInsertionPoint(dispatch);
  auto fresh = idr::CallOp::create(rewriter, call.getLoc(), dispatch->getResultTypes(), target,
                                   want.operands, /*arg_attrs=*/ArrayAttr(),
                                   /*res_attrs=*/ArrayAttr());
  SmallVector<Value> old(call.getArgs());
  rewriter.replaceOp(dispatch, fresh.getResults());
  for (Operation *step : llvm::reverse(want.consumer.steps()))
    rewriter.eraseOp(step);
  rewriter.eraseOp(call);
  eraseUnused(rewriter, old);
  return fresh;
}

} // namespace idr::specialize::detail
