// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// may-diverge: whether a run of a function may never end, as its row
// says. Eager evaluation runs a computation whose value goes unused, so a
// loop Idris did not prove to end still runs, and may run forever,
// wherever a pass moves its code, and every function that takes it in
// may never end either. The property reads the row, the effect system's
// one derivation of the body, which the verifier holds the body to: never
// the op that put the divergence there, so it states the same of a loop
// marked, a call of a function that may never end, or a cycle Idris did
// not prove.

#include "idr/Transforms/Expect.h"

#include "idr/IR/Effects/Vocabulary.h"
#include "idr/IR/IdrDialect.h"

using namespace mlir;

namespace idr::expect {

// Every function @f names, its copies among them, has a row holding
// divergence; each that does not is reported, with the row it has. A row
// is a fact of the program's functions, which only an idr.func carries:
// after lowering, upstream's functions carry none, so the property fails
// at each of them.
LogicalResult mayDiverge(const Request<Functions> &request) {
  LogicalResult held = success();
  for (FunctionOpInterface fn : request.argument.functions) {
    auto ours = dyn_cast<FuncOp>(fn.getOperation());
    if (!ours) {
      fail(fn->getLoc(), request.property)
          << where(fn) << " is lowered, and carries no row to hold divergence";
      held = failure();
      continue;
    }
    effects::Row row = ours.getRow();
    if (row.contains(effects::Atom::divergence))
      continue;
    fail(fn->getLoc(), request.property)
        << where(fn) << "'s row, " << convertRowToAttribute(fn->getContext(), row)
        << ", holds no divergence: as its row says, a run of it always ends";
    held = failure();
  }
  return held;
}

} // namespace idr::expect
