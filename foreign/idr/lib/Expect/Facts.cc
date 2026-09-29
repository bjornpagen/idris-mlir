// facts-as-marked: what lib/Facts answers about an op, stated on the op.
// A test marks an op `expect.facts = "..."` with the questions the answer is
// yes to, among `drop`, `move`, `delay` and `evaluate`, and the property
// fails wherever lib/Facts answers otherwise; the op itself is not changed.

#include "Expect/Expect.h"

import idr.facts;

using namespace mlir;

namespace {

// The questions lib/Facts answers yes to about `op`, in a fixed order.
std::string answers(Operation *op, SymbolTable &symbols) {
  auto call = dyn_cast<func::CallOp>(op);
  std::pair<StringRef, bool> questions[] = {
      {"drop", call && idr::facts::canDrop(call)},
      {"move", idr::facts::canMoveAcross(op)},
      {"delay", idr::facts::canDelay(op)},
      {"evaluate", idr::facts::canEvaluate(op, symbols).has_value()},
  };
  std::string out;
  for (auto [question, yes] : questions)
    if (yes)
      out += (out.empty() ? "" : " ") + question.str();
  return out;
}

} // namespace

LogicalResult idr::expect::factsAsMarked(ModuleOp module, StringRef) {
  SymbolTable symbols(module);
  bool held = true;
  module.walk([&](Operation *op) {
    auto marked = op->getAttrOfType<StringAttr>("expect.facts");
    if (!marked)
      return;
    std::string found = answers(op, symbols);
    if (found == marked.getValue())
      return;
    fail(op->getLoc(), "facts-as-marked")
        << "in " << where(op) << ", " << op->getName() << " answers \"" << found
        << "\", not \"" << marked.getValue() << "\"";
    held = false;
  });
  return success(held);
}
