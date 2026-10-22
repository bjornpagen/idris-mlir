// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The flow vocabulary's behaviour (FlowEdges.h): what a value carries, the
// type held at a point, and the helpers ops declare their edges with. An
// edge carries what the value that moves carries, so a word or a world
// moves along none. A value is followed whole, or into and out of a part of
// another, which is how the label solve keeps one set per anchor and
// ownership one state per value.

#include "idr/IR/Flow.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Match.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;
using namespace idr;

//===----------------------------------------------------------------------===//
// The vocabulary
//===----------------------------------------------------------------------===//

Carriers Carriers::of(Type type) {
  // A cell is the one type that is another value before it exists: the box
  // its init makes of it, a data value, which its type holds to be no cell.
  if (auto cell = dyn_cast<CellType>(type))
    type = cell.getValue();
  Carriers carriers;
  if (isClosureType(type))
    carriers = carriers | Carrier::Closure;
  if (isLazyType(type))
    carriers = carriers | Carrier::Suspension;
  if (holdsReferences(type))
    carriers = carriers | Carrier::Reference;
  return carriers;
}

std::optional<Type> FlowAnchor::slot() const {
  using Slot = std::optional<Type>;
  return idr::match(
      place,
      [](const Field &field) -> Slot {
        return unrestricted(field.data.ctor(field.ctor).fields[field.index]);
      },
      [](const Elements &elements) -> Slot { return elements.element; },
      [](const Forced &forced) -> Slot { return unrestricted(forced.lazy.getValue()); },
      [](const MemoState &state) -> Slot {
        return unrestricted(state.memo.ctor(state.memo.memo()->forced()).fields.front());
      },
      [](const Capture &) -> Slot { return std::nullopt; },
      [](const Hole &hole) -> Slot { return hole.dest.getValue(); });
}

std::optional<Type> FlowPoint::type() const {
  using Held = std::optional<Type>;
  return idr::match(
      at, [](Taken taken) -> Held { return unrestricted(taken.use->get().getType()); },
      [](Whole whole) -> Held { return unrestricted(whole.value.getType()); },
      [](const Part &part) -> Held { return part.anchor.slot(); },
      [](Parameter) -> Held { return std::nullopt; }, [](Result) -> Held { return std::nullopt; });
}

namespace {

// The type of what moves from `from` to `to`: the one end that says it.
std::optional<Type> movedType(const FlowPoint &from, const FlowPoint &to) {
  if (std::optional<Type> type = from.type())
    return type;
  return to.type();
}

} // namespace

void FlowEdges::add(Edge edge) {
  if (!edge.carriers.empty())
    list.push_back(edge);
}

void FlowEdges::flow(FlowPoint from, FlowPoint to, Carriers only) {
  if (std::optional<Type> type = movedType(from, to))
    add({Flow{from, to}, Carriers::of(*type) & only});
}

void FlowEdges::unify(FlowPoint a, FlowPoint b) {
  if (std::optional<Type> type = movedType(a, b))
    add({Unify{a, b}, Carriers::of(*type) & Carriers::labels()});
}

void FlowEdges::source(FlatSymbolRefAttr label, Value to) {
  add({Source{label, to}, Carriers::of(to.getType()) & Carriers::labels()});
}

void FlowEdges::fresh(Value to) {
  add({Fresh{to}, Carriers::of(to.getType()) & Carrier::Reference});
}

void FlowEdges::release(OpOperand &use) {
  add({Release{&use}, Carriers::of(use.get().getType()) & Carrier::Reference});
}

void FlowEdges::overwrite(FlowPoint place) {
  if (std::optional<Type> type = place.type())
    add({Overwrite{place}, Carriers::of(*type) & Carrier::Reference});
}

void FlowEdges::constant(Attribute part, Value to) {
  add({Constant{part, to}, Carriers::of(to.getType())});
}

void FlowEdges::dispatch(CallOpInterface call) {
  // The callee runs its labels; the arguments move into whatever runs.
  Carriers carriers = Carriers::of(cast<Value>(call.getCallableForCallee()).getType()) &
                      Carriers::labels();
  auto holdsReference = [](Value arg) {
    return Carriers::of(arg.getType()).contains(Carrier::Reference);
  };
  if (llvm::any_of(call.getArgOperands(), holdsReference))
    carriers = carriers | Carrier::Reference;
  add({Dispatch{call}, carriers});
}

