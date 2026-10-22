// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The flow vocabulary's behaviour (FlowEdges.h): what a value carries, the
// type held at a source or a place, and the helpers ops declare their edges
// with. An edge carries what the value that moves carries, so a word or a
// world moves along none. A value is followed whole, or into and out of a
// part of another, which is how the label solve keeps one set per anchor
// and ownership one state per value.

#include "idr/IR/Flow.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Match.h"

#include "llvm/ADT/Hashing.h"
#include "llvm/ADT/STLExtras.h"

#include <cstdint>

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
        return unrestricted(field.group.ctor(field.member, field.ctor).fields[field.index]);
      },
      [](const Elements &elements) -> Slot { return elements.element; },
      [](const Forced &forced) -> Slot { return unrestricted(forced.lazy.getValue()); },
      [](const MemoState &state) -> Slot {
        return unrestricted(state.memo.ctor(state.memo.memo()->forced()).fields.front());
      },
      [](const Capture &) -> Slot { return std::nullopt; },
      [](const Hole &hole) -> Slot { return hole.dest.getValue(); });
}

llvm::hash_code idr::hash_value(const FlowAnchor &anchor) {
  size_t kind = anchor.place.index();
  return idr::match(
      anchor.place,
      [&](const FlowAnchor::Field &field) {
        return llvm::hash_combine(kind, field.group, field.member,
                                  static_cast<std::uint32_t>(field.ctor), field.index);
      },
      [&](const FlowAnchor::Elements &elements) {
        return llvm::hash_combine(kind, elements.element);
      },
      [&](const FlowAnchor::Forced &forced) { return llvm::hash_combine(kind, forced.lazy); },
      [&](const FlowAnchor::MemoState &state) { return llvm::hash_combine(kind, state.memo); },
      [&](const FlowAnchor::Capture &capture) {
        return llvm::hash_combine(kind, capture.carrier, capture.index);
      },
      [&](const FlowAnchor::Hole &hole) { return llvm::hash_combine(kind, hole.dest); });
}

Value FlowSource::Part::value() const {
  return idr::match(
      of, [](Taken taken) { return taken.use->get(); }, [](Whole whole) { return whole.value; });
}

std::optional<OpOperand *> FlowSource::Part::taken() const {
  using Found = std::optional<OpOperand *>;
  return idr::match(
      of, [](Taken taken) -> Found { return taken.use; },
      [](Whole) -> Found { return std::nullopt; });
}

std::optional<Value> FlowSource::value() const {
  using Found = std::optional<Value>;
  return idr::match(
      at, [](Taken taken) -> Found { return taken.use->get(); },
      [](Whole whole) -> Found { return whole.value; },
      [](const Part &part) -> Found { return part.value(); },
      [](Parameter) -> Found { return std::nullopt; },
      [](Result) -> Found { return std::nullopt; });
}

std::optional<OpOperand *> FlowSource::taken() const {
  using Found = std::optional<OpOperand *>;
  return idr::match(
      at, [](Taken taken) -> Found { return taken.use; },
      [](Whole) -> Found { return std::nullopt; },
      [](const Part &part) -> Found { return part.taken(); },
      [](Parameter) -> Found { return std::nullopt; },
      [](Result) -> Found { return std::nullopt; });
}

std::optional<Type> FlowSource::type() const {
  using Held = std::optional<Type>;
  return idr::match(
      at, [](Taken taken) -> Held { return unrestricted(taken.use->get().getType()); },
      [](Whole whole) -> Held { return unrestricted(whole.value.getType()); },
      [](const Part &part) -> Held { return part.anchor.slot(); },
      [](Parameter) -> Held { return std::nullopt; }, [](Result) -> Held { return std::nullopt; });
}

std::optional<Value> FlowPlace::value() const {
  using Found = std::optional<Value>;
  return idr::match(
      at, [](FlowSource::Whole whole) -> Found { return whole.value; },
      [](const Part &part) -> Found { return part.of; },
      [](FlowSource::Parameter) -> Found { return std::nullopt; },
      [](FlowSource::Result) -> Found { return std::nullopt; });
}

std::optional<Type> FlowPlace::type() const {
  using Held = std::optional<Type>;
  return idr::match(
      at, [](FlowSource::Whole whole) -> Held { return unrestricted(whole.value.getType()); },
      [](const Part &part) -> Held { return part.anchor.slot(); },
      [](FlowSource::Parameter) -> Held { return std::nullopt; },
      [](FlowSource::Result) -> Held { return std::nullopt; });
}

namespace {

// The type of what moves into `to`: what the end it comes from says, or
// else what the place says.
std::optional<Type> movedType(std::optional<Type> from, const FlowPlace &to) {
  return from ? from : to.type();
}

} // namespace

void FlowEdges::add(Edge edge) {
  if (!edge.carriers.empty())
    list.push_back(edge);
}

void FlowEdges::flow(FlowSource from, FlowPlace to, Carriers only) {
  if (std::optional<Type> type = movedType(from.type(), to))
    add({Flow{from, to}, Carriers::of(*type) & only});
}

void FlowEdges::unify(FlowPlace a, FlowPlace b) {
  if (std::optional<Type> type = movedType(a.type(), b))
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

void FlowEdges::overwrite(Value of, FlowAnchor anchor) {
  if (std::optional<Type> type = anchor.slot())
    add({Overwrite{{of, anchor}}, Carriers::of(*type) & Carrier::Reference});
}

void FlowEdges::fill(Value of, FlowAnchor anchor) {
  if (std::optional<Type> type = anchor.slot())
    add({Fill{{of, anchor}}, Carriers::of(*type) & Carrier::Reference});
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

