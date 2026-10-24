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
  using Node = WalkNumbering::Node;
  SymbolTable &symbols = symbolsOf(request.module, request.analyses);
  const WalkNumbering &numbering = walkOf(request.module, request.analyses);
  SmallVector<Node> roots;
  for (Node fn : numbering.functions())
    if (cast<SymbolOpInterface>(numbering.op(fn).getOperation()).isPublic())
      roots.push_back(fn);
  // The answer of this one check, a bit per id, kept nowhere after it.
  BitSet<Node> reach(numbering.size());
  auto edges = [&](Node fn) { return callees(numbering, symbols, fn); };
  for (Node id : reachable(numbering, roots, edges))
    (void)reach.raise(id);
  bool held = true;
  for (Node id : numbering.functions()) {
    if (reach.test(id))
      continue;
    FunctionOpInterface fn = numbering.op(id);
    fail(fn->getLoc(), request.property) << where(fn) << " is reached from no root";
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
