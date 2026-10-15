// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// contified: every continuation became part of the function it continues.
// A function whose one use is a call from another function, which it
// calls back, is a continuation of that function (a case block of
// Idris's recursion through an `if`), which MLIR's inliner never inlines,
// and idr-contify inlines it there; which functions it was is the passes'
// business, that none is left is the property.

#include "idr/Transforms/Expect.h"

#include "idr/IR/IdrDialect.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::expect {

// The users are counted as idr-contify counts them, by upstream's map of
// symbol users. The root is called by no function of the program, so it
// is no continuation.
LogicalResult contified(ModuleOp module, AnalysisManager &, StringRef) {
  SymbolTableCollection tables;
  SymbolUserMap users(tables, programOf(module));
  bool held = true;
  for (FuncOp fn : programOf(module)->getRegion(0).getOps<FuncOp>()) {
    ArrayRef<Operation *> uses = users.getUsers(fn);
    if (uses.size() != 1)
      continue;
    auto call = dyn_cast<CallOp>(uses.front());
    auto caller = call ? call->getParentOfType<FuncOp>() : FuncOp();
    if (!caller || caller == fn)
      continue;
    if (llvm::none_of(users.getUsers(caller),
                      [&](Operation *user) { return user->getParentOfType<FuncOp>() == fn; }))
      continue;
    fail(call.getLoc(), "contified") << where(fn) << " is called once, from " << where(call)
                                      << ", and is still a function";
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
