// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// reached: every function of the program is reached from its roots, the
// functions its symbol table makes public (the program's root, and main
// once lowering has erased the program), by the symbols the bodies of the
// functions reached before it name. The frontend writes a function only
// where the program needs it, so of the module it emits this holds; a
// function no root reaches would be one written for nothing.

#include "idr/Transforms/Expect.h"

#include "llvm/ADT/SmallPtrSet.h"

using namespace mlir;

namespace idr::expect {

LogicalResult reached(const Request<Nothing> &request) {
  SymbolTable &symbols = symbolsOf(request.module, request.analyses);
  SmallVector<FunctionOpInterface> functions = functionsOf(request.module);
  SmallVector<Operation *> roots;
  for (FunctionOpInterface fn : functions)
    if (cast<SymbolOpInterface>(fn.getOperation()).isPublic())
      roots.push_back(fn);
  SmallVector<Operation *> found =
      reachable(roots, [&](Operation *fn) { return callees(symbols, fn); });
  // The answer of this one check, asked once and kept nowhere after it.
  llvm::SmallPtrSet<Operation *, 16> reach(found.begin(), found.end());
  bool held = true;
  for (FunctionOpInterface fn : functions) {
    if (reach.contains(fn))
      continue;
    fail(fn.getLoc(), request.property) << where(fn) << " is reached from no root";
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
