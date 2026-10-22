// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// contified: every continuation became part of the function it continues.
// A function whose one use is a call from another function, which it
// calls back, is a continuation of that function (a case block of
// Idris's recursion through an `if`), which MLIR's inliner never inlines,
// and idr-contify inlines it there; which functions it was is the passes'
// business, that none is left is the property.

#include "Checks.h"

#include "mlir/Interfaces/CallInterfaces.h"
#include "mlir/Interfaces/FunctionInterfaces.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::expect {

// The users are counted as idr-contify counts them, by upstream's map of
// symbol users, and the calls by upstream's call interface, so the program
// of any stage is read alike. The root is called by no function of the
// program, so it is no continuation.
LogicalResult contified(const Request<Nothing> &request) {
  ModuleOp module = request.module;
  Operation *program = programOf(module);
  SymbolTableCollection tables;
  SymbolUserMap users(tables, program);
  bool held = true;
  for (FunctionOpInterface fn : program->getRegion(0).getOps<FunctionOpInterface>()) {
    ArrayRef<Operation *> uses = users.getUsers(fn);
    if (uses.size() != 1)
      continue;
    auto call = dyn_cast<CallOpInterface>(uses.front());
    auto caller = call ? call->getParentOfType<FunctionOpInterface>() : FunctionOpInterface();
    if (!caller || caller == fn)
      continue;
    if (llvm::none_of(users.getUsers(caller), [&](Operation *user) {
          return user->getParentOfType<FunctionOpInterface>() == fn;
        }))
      continue;
    fail(call->getLoc(), request.property) << where(fn) << " is called once, from " << where(call)
                                           << ", and is still a function";
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
