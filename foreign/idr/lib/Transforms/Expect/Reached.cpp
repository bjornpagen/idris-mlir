// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// reached: every function of the program is reached from its roots, the
// functions its symbol table makes public (the program's root, and main
// once lowering has erased the program), by the symbols the bodies of the
// functions reached before it name. The frontend writes a function only
// where the program needs it, so of the module it emits this holds; a
// function no root reaches would be one written for nothing.

#include "idr/Transforms/Expect.h"

using namespace mlir;

namespace idr::expect {

LogicalResult reached(const Request<Nothing> &request) {
  SymbolTable &symbols = symbolsOf(request.module, request.analyses);
  const FunctionNumbering &numbering = numberingOf(request.module, request.analyses);
  SmallVector<FunctionOpInterface> functions = functionsOf(request.module);
  SmallVector<Operation *> roots;
  for (FunctionOpInterface fn : functions)
    if (cast<SymbolOpInterface>(fn.getOperation()).isPublic())
      roots.push_back(fn);
  // The answer of this one check, a bit per function, kept nowhere after it.
  BitSet<FunctionNumbering::Node> reach(numbering.count());
  for (FunctionNumbering::Node id :
       reachable(numbering, roots,
                 [&](FunctionNumbering::Node fn) { return callees(numbering, symbols, fn); }))
    (void)reach.raise(id);
  bool held = true;
  for (FunctionNumbering::Node id : numbering.count().ids()) {
    if (reach.test(id))
      continue;
    fail(numbering[id]->getLoc(), request.property) << where(numbering[id]) << " is reached from no root";
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
