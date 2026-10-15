// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Calling a node: the one way a call becomes a call of a specialization or
// raise node. It needs only the node's name: the node's function need not
// exist yet, and what a call may do is its callee's.
//
// The call passes one operand per parameter the node is built with, though
// no verifier sees the node yet: for a specialization one per hole of its
// key, in the key's order, a leaf of the call or a constant lifted out of
// the key and built at the call at the hole's type, and the node takes one
// parameter per hole in that order, of that type; for a raise the call's
// operands and then the consumer's free values, and the node takes its
// callee's parameters and then the consumer's. Every other call in idr-optimize is one the verifier checked
// on its input, or a clone of one that inlining or a build made, so every
// call passes one argument per parameter of its callee.
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Specialize.h"

#include "llvm/ADT/STLExtras.h"

#include <cassert>

using namespace mlir;

namespace idr::specialize::detail {

SmallVector<Value> operandsOf(RewriterBase &rewriter, idr::CallOp call, const Want &want,
                              const Key &key, ArrayRef<Source> sources,
                              const Schedule &schedule) {
  SmallVector<Type> types = std::visit(
      llvm::makeVisitor(
          [&](SpecKeyAttr spec) {
            SmallVector<Type> out;
            // The origin is final: the callee, or the origin of the node it is.
            idr::FuncOp origin = schedule.lookup(spec.getOrigin());
            assert(origin && "a spec key's origin is a function of the program");
            for (auto [pattern, type] :
                 llvm::zip_equal(spec.getPatterns(), origin.getArgumentTypes()))
              holeTypes(pattern, type, out);
            return out;
          },
          // A raise is never lifted: its operands are all kept.
          [](KeyRaiseAttr) { return SmallVector<Type>(); }),
      key);
  rewriter.setInsertionPoint(call);
  SmallVector<Value> operands;
  for (auto [hole, source] : llvm::enumerate(sources))
    operands.push_back(std::visit(
        llvm::makeVisitor([&](Kept kept) { return want.operands[kept.hole]; },
                          [&](const Lifted &lifted) {
                            return rebuild(rewriter, call.getLoc(), lifted.constant, types[hole],
                                           {});
                          }),
        source));
  return operands;
}

idr::CallOp redirect(RewriterBase &rewriter, idr::CallOp call, FlatSymbolRefAttr target,
                     const Want &want) {
  // Raising replaces what the dispatch returns; specialization the call.
  // Either way the node returns what the replaced op does.
  Operation *replaced = want.consumer ? static_cast<Operation *>(want.consumer->dispatch)
                                      : call.getOperation();
  rewriter.setInsertionPoint(replaced);
  auto fresh = idr::CallOp::create(rewriter, call.getLoc(), replaced->getResultTypes(), target,
                                   want.operands, /*arg_attrs=*/ArrayAttr(),
                                   /*res_attrs=*/ArrayAttr());
  SmallVector<Value> old(call.getArgs());
  rewriter.replaceOp(replaced, fresh.getResults());
  if (const std::optional<Consumer> &consumer = want.consumer) {
    // The steps from the call's result to the dispatch, each the one use
    // of the one before: erased from the dispatch back.
    for (Operation *step : llvm::reverse(consumer->steps()))
      rewriter.eraseOp(step);
    rewriter.eraseOp(call);
  }
  eraseUnused(rewriter, old);
  return fresh;
}

} // namespace idr::specialize::detail
