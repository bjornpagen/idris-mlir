// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The values a view of which takes a reference of its own, shared where
// they are consumed, before exclusivity's solve. The taint crosses
// calls: a callee that dups a parameter it borrows taints what its callers
// pass there, so this is one walk of the module, made before any function
// is committed.
#include "idr/Analysis/Ownership.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ownership.h"
#include "idr/Transforms/Ownership.h"

#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/SetVector.h"

using namespace mlir;

namespace idr::ownership {

// A value some view of which takes a reference of its own (idr.dup, here
// or in a callee that borrows the value) has shared cells by the time it is
// consumed, whatever it alone reached when it was made. Its consuming use
// gets it shared (idr.share): the solver reads the shared value there, and
// the value itself keeps what its provenance proves, which its callee's or
// constructor's type must agree with.
void shareTainted(ModuleOp module, SymbolTable &symbols) {
  llvm::SetVector<Value> tainted;
  DenseMap<Operation *, SmallVector<unsigned>> borrowedRoots;
  module.walk([&](DupOp dup) {
    Value root = viewRoot(dup.getValue());
    if (followed(root))
      tainted.insert(root);
    auto arg = dyn_cast<BlockArgument>(root);
    auto fn = arg ? dyn_cast<FuncOp>(arg.getOwner()->getParentOp()) : FuncOp();
    if (fn && !isOwned(arg.getType()))
      borrowedRoots[fn].push_back(arg.getArgNumber());
  });
  module.walk([&](CallOp call) {
    auto fn = symbols.lookup<FuncOp>(call.getCalleeAttr().getAttr());
    auto it = fn ? borrowedRoots.find(fn) : borrowedRoots.end();
    if (it == borrowedRoots.end())
      return;
    for (unsigned index : it->second)
      if (Value root = viewRoot(call.getArgOperands()[index]); followed(root))
        tainted.insert(root);
  });
  // The consuming uses are found first and shared after: each share is a
  // new use of the value.
  SmallVector<OpOperand *> consuming;
  for (Value value : tainted)
    for (OpOperand &use : value.getUses())
      if (useOf(use, &symbols) == Use::Consume)
        consuming.push_back(&use);
  IRRewriter rewriter(module.getContext());
  for (OpOperand *use : consuming) {
    Operation *owner = use->getOwner();
    rewriter.setInsertionPoint(owner);
    Value shared = ShareOp::create(rewriter, owner->getLoc(), use->get().getType(), use->get());
    rewriter.modifyOpInPlace(owner, [&] { use->set(shared); });
  }
}

} // namespace idr::ownership
