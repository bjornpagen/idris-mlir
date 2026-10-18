// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The inliner's rules for the dialect, as func's are for its own: every
// call may be inlined, and every op and region may move into another
// function. Which calls are worth it, no_inline among them, is idr-inline's
// decision; a callee that ends in ub.unreachable is decided by the
// inliner itself, as for func.func.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Func.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/Transforms/InliningUtils.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;
using namespace idr;

namespace {

struct IdrInlinerInterface : DialectInlinerInterface {
  using DialectInlinerInterface::DialectInlinerInterface;

  // Every call may go anywhere. A callee's body is one block, its region's
  // constraint, so it goes in as that block: on the fast path when it ends
  // in idr.return; and, when it ends in ub.unreachable, which does not
  // return, by the ub dialect's own hooks, as that block and the rest of
  // the caller's block after it, which nothing reaches and which each site
  // that inlines erases after its loop with upstream's
  // eraseUnreachableBlocks, nested regions included, so every region is
  // one block again.
  bool isLegalToInline(Operation *, Operation *, bool) const final { return true; }
  bool isLegalToInline(Region *, Region *, bool, IRMapping &) const final { return true; }
  bool isLegalToInline(Operation *, Region *, bool, IRMapping &) const final { return true; }

  // The callee's one block: the call's results are what its return gives
  // back, and the inliner erases the return.
  void handleTerminator(Operation *op, ValueRange valuesToRepl) const final {
    auto ret = cast<ReturnOp>(op);
    for (auto [replaced, value] : llvm::zip_equal(valuesToRepl, ret.getOperands()))
      replaced.replaceAllUsesWith(value);
  }
};

} // namespace

void idr::addInlinerInterface(IdrDialect &dialect) {
  dialect.addInterfaces<IdrInlinerInterface>();
}
