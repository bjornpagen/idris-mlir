// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The boundaries of one function where counting meets upstream's buffer
// ops, made before idr-rc-grades reads the program: reset/reuse and borrow
// inference decide by which use consumes a value, so they read the
// boundaries that placement then counts. No loop of linalg's holds a
// reference in its payload (the program's verifier holds that from the
// first stage on), so counting meets the buffers only at their loads,
// stores and allocations.
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Ownership.h"

#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/IR/PatternMatch.h"

using namespace mlir;

namespace idr::ownership {

// The two boundaries, where upstream's buffer ops see plain carriers: a
// fresh allocation's reference is taken over by an idr.own.adopt right
// after it, which every other use reads instead; and the value a store of
// an element that holds references writes is handed to it by an
// idr.own.give, which consumes the owned value and gives the store its
// plain carrier. Neither changes a count.
void boundaries(FuncOp fn) {
  SmallVector<memref::AllocOp> allocs;
  SmallVector<memref::StoreOp> stores;
  fn.walk([&](Operation *op) {
    if (auto alloc = dyn_cast<memref::AllocOp>(op))
      allocs.push_back(alloc);
    else if (auto store = dyn_cast<memref::StoreOp>(op);
             store && holdsReferences(store.getValueToStore().getType()))
      stores.push_back(store);
  });
  IRRewriter rewriter(fn.getContext());
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

} // namespace idr::ownership
