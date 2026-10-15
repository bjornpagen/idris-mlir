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

// Whether `a` is of `b`'s carrier and every label of `a` is one of `b`'s.
bool within(const Key &a, const Key &b) {
  return a.carrier == b.carrier && llvm::all_of(a.labels, [&](Attribute label) {
           return llvm::is_contained(b.labels, label);
         });
}

} // namespace

Slot Slots::sinkKey(OpOperand &use) const {
  std::optional<FlowPoint> sink = analysis.sinkOf(use);
  return sink ? keyAt(*sink) : std::nullopt;
}

// A closure, suspension or constant whose every use moves it into slots of
// one key with its labels and more takes that key.
void Slots::widen() {
  program.walk([&](Operation *op) {
    if (!isa<ClosureOp, SuspendOp, ConstantOp>(op) || !carriesLabels(op->getResultTypes()[0]))
      return;
    Value value = op->getResult(0);
    Slot common;
    for (OpOperand &use : value.getUses()) {
      Slot to = sinkKey(use);
      if (!to || (common && *common != *to))
        return;
      common = to;
    }
    if (common && within(*keyOf(value), *common))
      widened[value] = *common;
  });
}

} // namespace idr::defunctionalize
