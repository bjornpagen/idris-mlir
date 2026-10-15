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

#include "llvm/ADT/STLExtras.h"

#include <variant>

using namespace mlir;
using namespace idr;

//===----------------------------------------------------------------------===//
// The vocabulary
//===----------------------------------------------------------------------===//

Carriers Carriers::of(Type type) {
  Carriers carriers;
  if (isClosureType(type))
    carriers = carriers | Carrier::Closure;
  if (isLazyType(type))
    carriers = carriers | Carrier::Suspension;
  if (holdsReferences(type))
    carriers = carriers | Carrier::Reference;
  return carriers;
}

namespace {

// What `anchor` holds, where its own type says: a field's type, the
// element type, a suspension's value. A capture's is its label's
// parameter's, a memo sum's forced state its forced constructor's field,
// which only the label and the body say.
std::optional<Type> slotOf(const FlowAnchor &anchor) {
  return std::visit(
      llvm::makeVisitor(
          [](const FlowAnchor::Field &field) -> std::optional<Type> {
            return unrestricted(cast<DataType>(field.data).getCtor(field.ctor).fields[field.index]);
          },
          [](const FlowAnchor::Elements &elements) -> std::optional<Type> {
            return elements.element;
          },
          [](const FlowAnchor::Forced &forced) -> std::optional<Type> {
            if (auto lazy = dyn_cast<LazyType>(forced.lazy))
              return unrestricted(lazy.getValue());
            return std::nullopt;
          },
          [](const FlowAnchor::Capture &) -> std::optional<Type> { return std::nullopt; },
          [](const FlowAnchor::Hole &hole) -> std::optional<Type> {
            return unrestricted(cast<DestType>(hole.dest).getValue());
          }),
      anchor.place);
}

} // namespace

std::optional<Type> FlowPoint::type() const {
  return std::visit(
      llvm::makeVisitor(
          [](FlowPoint::Taken taken) -> std::optional<Type> {
            return unrestricted(taken.use->get().getType());
          },
          [](FlowPoint::Whole whole) -> std::optional<Type> {
            return unrestricted(whole.value.getType());
          },
          [](const FlowPoint::Part &part) { return slotOf(part.anchor); },
          [](FlowPoint::Parameter) -> std::optional<Type> { return std::nullopt; },
          [](FlowPoint::Result) -> std::optional<Type> { return std::nullopt; }),
      at);
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

