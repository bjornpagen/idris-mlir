// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The keys: every slot's carrier and the labels the solve found for it,
// and every key the program may ask for, each given a dense id in the order
// met, which is the order every walk over the keys takes.
//
// A parameter's and a result's key are their function's, keyed once before
// anything else, so no function is read while another is rewritten; a
// part's is its anchor's, the same for every value of its kind; a value's
// is its own point's, unless the widening gave it the one key all its uses
// move it into.

#include "idr/Analysis/Labels.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Defunctionalize.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::defunctionalize {

Decision::Decision(ProgramOp top, const Labels &solve)
    : program(top), labels(solve), ctx(top.getContext()) {}

Slot Decision::keyWith(Type carrier, const FlowPoint &point) const {
  if (!carriesLabels(carrier))
    return std::nullopt;
  return Key{unrestricted(carrier), labels.labelsOf(point)};
}

// What every value of a kind holds at `anchor`. A capture has no slot of
// its own: a closure's parts are its label's parameters.
Slot Decision::anchorKey(const FlowAnchor &anchor) const {
  std::optional<Type> carrier = anchor.slot();
  if (!carrier || !carriesLabels(*carrier))
    return std::nullopt;
  return Key{unrestricted(*carrier), labels.labelsOf(anchor)};
}

Slot Decision::keyOf(Value value) const {
  if (auto it = widened.find(value); it != widened.end())
    return it->second;
  return keyWith(value.getType(), FlowPoint::of(value));
}

Slot Decision::sinkOf(OpOperand &use) const {
  std::optional<FlowPoint> sink = labels.sinkOf(use);
  if (!sink)
    return std::nullopt;
  return idr::match(
      sink->at, [&](FlowPoint::Taken taken) { return keyOf(taken.use->get()); },
      [&](FlowPoint::Whole whole) { return keyOf(whole.value); },
      [&](const FlowPoint::Part &part) { return anchorKey(part.anchor); },
      [&](FlowPoint::Parameter param) {
        return signature(param.function.getAttr()).arguments[param.index];
      },
      [&](FlowPoint::Result result) {
        return signature(result.function.getAttr()).results[result.index];
      });
}

// A key, and a lazy key's forced state, which its family's `forced` field
// holds.
void Decision::note(const Slot &slot) {
  if (!slot || ids.contains(*slot))
    return;
  ids.try_emplace(*slot, static_cast<KeyId>(families.size()));
  families.push_back(Family{*slot, DataType(), FlatSymbolRefAttr()});
  if (carrierOf(*slot) == Carrier::Lazy) {
    auto lazy = cast<LazyType>(slot->carrier);
    note(anchorKey(FlowAnchor::forcedOf(lazy)));
    noteType(lazy.getValue());
  }
}

// The slots a type holds that are no value's: the fields of each data
// family met in it, a closure's signature included, and the elements of
// each shaped type. Each type is walked once over the whole decision.
void Decision::noteType(Type type) {
  AttrTypeWalker walker;
  walker.addWalk([&](DataType data) {
    for (Tag tag : data.possibleTags())
      if (std::optional<SmallVector<Type>> fields = data.determinedFields(tag))
        for (auto [i, field] : llvm::enumerate(*fields))
          if (carriesLabels(field))
            note(anchorKey(FlowAnchor::fieldOf(data, tag, static_cast<unsigned>(i))));
  });
  walker.addWalk([&](ShapedType shaped) {
    if (carriesLabels(shaped.getElementType()))
      note(anchorKey(FlowAnchor::elementsOf(shaped.getElementType())));
  });
  walker.walk(type);
}

// A closure, suspension or constant whose every use moves it into slots of
// one key with its labels and more takes that key, so no coercion follows
// it. Read off each op's flow: what makes a carrier value is an edge's
// source, which the op's flow interface declares.
void Decision::widen() {
  FlowEdges edges;
  program.walk([&](FlowOpInterface flow) {
    Operation *op = flow.getOperation();
    if (op->getNumResults() != 1 || !carriesLabels(op->getResult(0).getType()))
      return;
    Value value = op->getResult(0);
    edges.clear();
    flow.getFlowEdges(edges);
    bool made = llvm::any_of(edges.edges(), [&](const FlowEdges::Edge &edge) {
      return idr::match(
          edge.move, [&](const FlowEdges::Source &source) { return source.to == value; },
          [&](const FlowEdges::Constant &constant) { return constant.to == value; },
          [](const auto &) { return false; });
    });
    if (!made)
      return;
    Slot common;
    for (OpOperand &use : value.getUses()) {
      Slot to = sinkOf(use);
      if (!to || (common && *common != *to))
        return;
      common = to;
    }
    Slot own = keyOf(value);
    if (common && own && common->carrier == own->carrier &&
        labels::within(own->labels, common->labels))
      widened[value] = *common;
  });
}

} // namespace idr::defunctionalize
