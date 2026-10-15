// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// facts-as-marked: what the dialect answers about an op, stated on the op.
// A test marks an op `expect.facts = "..."` with the questions the answer is
// yes to, among `drop`, `move`, `delay` and `merge`, and the property fails
// wherever the dialect answers otherwise; the op itself is not changed.
//
// Each question is asked as the pass that asks it asks it, so the property
// computes no effect of its own. Whether an unused op is dead and whether
// two equal ops are one value are upstream's dead code removal's and CSE's
// questions, which read the op's own effects. Whether an op may move across
// anything and whether it may be delayed are the dialect's rewrites'
// questions, which know the program's functions, so a call answers them
// with its callee's effects. A call holds no effects of its own and
// declares every effect to upstream, so no call is ever dead or merged
// here: idr-pure-calls drops and merges the calls of pure callees.

#include "idr/Transforms/Expect.h"

#include "idr/IR/Flow.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/Interfaces/SideEffectInterfaces.h"

using namespace mlir;

namespace idr::expect {

namespace {

// The questions answered yes about `op`, in a fixed order: whether it is
// dead once nothing reads it, whether it may be moved across anything,
// whether it may be delayed, and whether two equal ones are one value,
// which an op that allocates its result never is: no two cells become one.
std::string answers(Operation *op, const CalleeEffects &callees) {
  std::pair<StringRef, bool> questions[] = {
      {"drop", isOpTriviallyDead(op)},
      {"move", onlyAllocates(op, &callees)},
      {"delay", !performsIO(op, &callees)},
      {"merge", isMemoryEffectFree(op)},
  };
  std::string out;
  for (auto [question, yes] : questions)
    if (yes)
      out += (out.empty() ? "" : " ") + question.str();
  return out;
}

} // namespace

LogicalResult factsAsMarked(ModuleOp module, AnalysisManager &analyses, StringRef) {
  const CalleeEffects callees{symbolsOf(module, analyses)};
  bool held = true;
  module.walk([&](Operation *op) {
    auto marked = op->getAttrOfType<StringAttr>("expect.facts");
    if (!marked)
      return;
    std::string found = answers(op, callees);
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
