// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Where each use moves its value: the slot the solve recorded for it, one
// per operand, from the edges its op declares. A closure, suspension or
// constant made only to be moved into one slot is made in that slot's key,
// so that it needs no coercion.

#include "idr/IR/IdrDialect.h"
#include "idr/Analysis/Labels.h"
#include "idr/IR/Flow.h"
#include "idr/Transforms/Defunctionalize.h"

#include "mlir/IR/BuiltinOps.h"

#include "llvm/ADT/STLExtras.h"

#include <optional>

using namespace mlir;

namespace idr::defunctionalize {

namespace {

// Whether every label of `a` is one of `b`'s; both are sorted by name.
bool within(const Key &a, const Key &b) {
  return a.first == b.first && llvm::all_of(a.second, [&](Attribute label) {
           return llvm::is_contained(b.second, label);
         });
}

} // namespace

Key Slots::sinkKey(OpOperand &use) const {
  std::optional<FlowPoint> sink = analysis.sinkOf(use);
  return sink ? keyAt(*sink) : Key();
}

// A closure, suspension or constant whose every use moves it into slots of
// one key with its labels and more takes that key.
void Slots::widen() {
  program.walk([&](Operation *op) {
    if (!isa<ClosureOp, SuspendOp, ConstantOp>(op) || !carriesLabels(op->getResultTypes()[0]))
      return;
    Value value = op->getResult(0);
    std::optional<Key> common;
    for (OpOperand &use : value.getUses()) {
      Key to = sinkKey(use);
      if (!to.first || (common && *common != to))
        return;
      common = to;
    }
    if (common && within(keyOf(value), *common))
      widened[value] = *common;
  });
}

} // namespace idr::defunctionalize
