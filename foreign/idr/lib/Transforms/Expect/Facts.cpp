// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// facts-as-marked: what the dialect answers about an op, stated on the op.
// A test marks an op `expect.facts = "..."` with the questions the answer is
// yes to, among `drop`, `move`, `delay` and `merge`, and the property fails
// wherever the dialect answers otherwise; the op itself is not changed.
// The answers are the ops' own effects, and a call's are its callee's:
// the call carries none, so the property asks the dialect as every pass
// does and computes no effect of its own.

#include "idr/Transforms/Expect.h"

#include "idr/IR/IdrDialect.h"

#include "mlir/Interfaces/SideEffectInterfaces.h"

using namespace mlir;

namespace idr::expect {

namespace {

// The questions the dialect answers yes to about `op`, in a fixed order:
// whether an unused call may be dropped, whether the op may be moved
// across anything, whether it may be delayed, and whether two equal ones
// are one value, which an op that allocates its result never is: no two
// cells become one.
std::string answers(Operation *op) {
  auto call = dyn_cast<CallOp>(op);
  std::pair<StringRef, bool> questions[] = {
      {"drop", call && call->use_empty() && onlyAllocates(call)},
      {"move", onlyAllocates(op)},
      {"delay", !performsIO(op)},
      {"merge", isMemoryEffectFree(op)},
  };
  std::string out;
  for (auto [question, yes] : questions)
    if (yes)
      out += (out.empty() ? "" : " ") + question.str();
  return out;
}

} // namespace

LogicalResult factsAsMarked(ModuleOp module, AnalysisManager &, StringRef) {
  bool held = true;
  module.walk([&](Operation *op) {
    auto marked = op->getAttrOfType<StringAttr>("expect.facts");
    if (!marked)
      return;
    std::string found = answers(op);
    if (found == marked.getValue())
      return;
    fail(op->getLoc(), "facts-as-marked") << "in " << where(op) << ", " << op->getName()
                                          << " answers \"" << found << "\", not \""
                                          << marked.getValue() << "\"";
    held = false;
  });
  return success(held);
}

} // namespace idr::expect
