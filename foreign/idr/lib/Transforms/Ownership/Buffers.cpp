// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The buffers of one function in the form counting counts, made before
// idr-rc reads the program: reset/reuse and borrow inference decide by which
// use consumes a value, so they read the loads, stores and boundaries that
// placement then counts.
#include "idr/Analysis/Ownership.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Ownership.h"

#include "mlir/Dialect/Linalg/IR/Linalg.h"
#include "mlir/Dialect/Linalg/Transforms/Transforms.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/IR/PatternMatch.h"

using namespace mlir;

namespace idr::ownership {

namespace {

// A loop over buffers whose payload takes or yields an element that holds
// references becomes its scf.for loops: a payload's arguments have the
// element's type, which no grade may change, and a named op's region is
// rebuilt where it is parsed. The loops' loads and stores are what counting
// grades. A loop over words keeps its form. The loops load every input
// element whether the payload reads it or not; an element nothing reads
// takes no reference, so its load is no read at all, and goes.
LogicalResult loopCountedElements(RewriterBase &rewriter, FuncOp fn) {
  SmallVector<linalg::LinalgOp> loops;
  fn.walk([&](linalg::LinalgOp loop) {
    if (loop.hasPureBufferSemantics() &&
        llvm::any_of(loop.getBlock()->getArgumentTypes(), [](Type type) { return counted(type); }))
      loops.push_back(loop);
  });
  for (linalg::LinalgOp loop : loops) {
    rewriter.setInsertionPoint(loop);
    if (failed(linalg::linalgOpToLoops(rewriter, loop)))
      return loop->emitOpError("idr-rc: internal error: a loop over buffers whose elements hold "
                               "references has no loops of its own");
    rewriter.eraseOp(loop);
  }
  SmallVector<memref::LoadOp> unread;
  fn.walk([&](memref::LoadOp load) {
    if (load->use_empty() && counted(load.getType()))
      unread.push_back(load);
  });
  for (memref::LoadOp load : unread)
    rewriter.eraseOp(load);
  return success();
}

// The two boundaries where counting meets upstream's buffer ops, which see
// plain carriers: a fresh allocation's reference is taken over by an
// idr.own.adopt right after it, which every other use reads instead; and
// the value a store of an element that holds references writes is handed
// to it by an idr.own.give, which consumes the owned value and gives the
// store its plain carrier. Neither changes a count.
void boundaries(RewriterBase &rewriter, FuncOp fn) {
  SmallVector<memref::AllocOp> allocs;
  SmallVector<memref::StoreOp> stores;
  fn.walk([&](Operation *op) {
    if (auto alloc = dyn_cast<memref::AllocOp>(op))
      allocs.push_back(alloc);
    else if (auto store = dyn_cast<memref::StoreOp>(op);
             store && counted(store.getValueToStore().getType()))
      stores.push_back(store);
  });
  for (memref::AllocOp alloc : allocs) {
    rewriter.setInsertionPointAfter(alloc);
    auto adopt = OwnAdoptOp::create(rewriter, alloc.getLoc(), alloc.getResult());
    rewriter.replaceAllUsesExcept(alloc.getResult(), adopt.getResult(), adopt);
  }
  for (memref::StoreOp store : stores) {
    rewriter.setInsertionPoint(store);
    auto give = OwnGiveOp::create(rewriter, store.getLoc(), store.getValueToStore());
    // The stored value is the store's operand 0 (getValueToStore).
    rewriter.modifyOpInPlace(store, [&] { store->setOperand(0, give.getResult()); });
  }
}

} // namespace

LogicalResult bufferForms(FuncOp fn) {
  IRRewriter rewriter(fn.getContext());
  if (failed(loopCountedElements(rewriter, fn)))
    return failure();
  boundaries(rewriter, fn);
  return success();
}

} // namespace idr::ownership
