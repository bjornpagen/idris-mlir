// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Calling a node: the one way a call becomes a call of a specialization or
// raise node. It needs only the node's name and, once the node is final,
// its effects: the node's function need not exist yet.
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Specialize.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::specialize::detail {

idr::CallOp redirect(RewriterBase &rewriter, idr::CallOp call, FlatSymbolRefAttr target,
                     idr::EffectAttr effects, const Want &want) {
  // Raising replaces what the dispatch returns; specialization the call.
  // Either way the node returns what the replaced op does.
  Operation *replaced = want.consumer ? static_cast<Operation *>(want.consumer->dispatch)
                                      : call.getOperation();
  rewriter.setInsertionPoint(replaced);
  auto fresh = idr::CallOp::create(rewriter, call.getLoc(), replaced->getResultTypes(), target,
                                   want.operands, /*arg_attrs=*/ArrayAttr(),
                                   /*res_attrs=*/ArrayAttr(), effects);
  SmallVector<Value> old(call.getArgs());
  rewriter.replaceOp(replaced, fresh.getResults());
  if (const std::optional<Consumer> &consumer = want.consumer) {
    // The steps from the call's result to the dispatch, each the one use
    // of the one before: erased from the dispatch back.
    if (consumer->use)
      rewriter.eraseOp(consumer->use);
    if (consumer->field)
      rewriter.eraseOp(consumer->field);
    if (consumer->exit) {
      rewriter.eraseOp(consumer->exit);
      rewriter.eraseOp(consumer->enter);
    }
    rewriter.eraseOp(call);
  }
  eraseUnused(rewriter, old);
  return fresh;
}

} // namespace idr::specialize::detail
