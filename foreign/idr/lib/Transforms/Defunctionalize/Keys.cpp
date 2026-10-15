// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The key of every slot (its carrier and the labels the solve found for
// it), every key the program may ask for, and the plan each function's
// conversion reads.

#include "idr/IR/IdrDialect.h"
#include "idr/Analysis/Labels.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Symbols.h"
#include "idr/Transforms/Defunctionalize.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::defunctionalize {

namespace {

// The arguments a label of `carrier` is called with besides its captures:
// a closure's, or none, since every parameter of a suspended function is a
// capture.
unsigned arity(Type carrier) {
  auto fn = dyn_cast<FnType>(carrier);
  return fn ? static_cast<unsigned>(fn.getInputs().size()) : 0;
}

} // namespace

// Every function's signature is keyed first, since every other key of a
// parameter or a result reads it; then the widening, which reads the sinks;
// then every key the program may ask for, from every value and every type
// any op, value or attribute names.
Slots::Slots(ProgramOp top, Labels &labels, SymbolTable &symbols)
    : program(top), analysis(labels), table(symbols), ctx(top.getContext()) {
  types.addWalk([this](DataType data) { noteData(data); });
  types.addWalk([this](ShapedType shaped) { noteSlot(elementKey(shaped.getElementType())); });
  for (FuncOp fn : program.getOps<FuncOp>()) {
    Signature &sig = signatures[fn.getSymNameAttr()];
    sig.type = fn.getFunctionType();
    for (BlockArgument arg : fn.getArguments())
      sig.arguments.push_back(keyWith(arg.getType(), FlowPoint::of(Value(arg))));
    auto name = FlatSymbolRefAttr::get(fn.getSymNameAttr());
    for (auto [j, type] : llvm::enumerate(sig.type.getResults()))
      sig.results.push_back(keyWith(type, FlowPoint::result(name, static_cast<unsigned>(j))));
  }
  widen();
  for (FuncOp fn : program.getOps<FuncOp>()) {
    const Signature &sig = signatures.find(fn.getSymNameAttr())->second;
    for (const Slot &slot : llvm::concat<const Slot>(sig.arguments, sig.results))
      noteSlot(slot);
    // The function itself is walked too: its type is an attribute of it.
    fn.walk([&](Operation *op) {
      types.walk(op->getAttrDictionary());
      for (Value result : op->getResults())
        noteValue(result);
      for (Region &region : op->getRegions())
        for (Block &block : region)
          for (Value arg : block.getArguments())
            noteValue(arg);
    });
  }
}

// The key of a slot of `carrier` at `point`: none for a carrier that holds
// no label.
Slot Slots::keyWith(Type carrier, const FlowPoint &point) const {
  if (!carriesLabels(carrier))
    return std::nullopt;
  return Key{unrestricted(carrier), analysis.labelsOf(point)};
}

// The key of what is held at `point`. A parameter's and a result's are
// their function's, keyed once before anything else, so that no function
// is read while another converts; a part's is its anchor's.
Slot Slots::keyAt(const FlowPoint &point) const {
  return std::visit(
      llvm::makeVisitor(
          [&](FlowPoint::Taken taken) { return keyOf(taken.use->get()); },
          [&](FlowPoint::Whole whole) { return keyWith(whole.value.getType(), point); },
          [&](const FlowPoint::Part &part) { return anchorKey(part.anchor); },
          [&](FlowPoint::Parameter param) {
            return argumentKey(param.function.getAttr(), param.index);
          },
          [&](FlowPoint::Result result) {
            return resultKey(result.function.getAttr(), result.index);
          }),
      point.at);
}

// The key of what every value of a kind holds at `anchor`. What a closure
// or a suspension holds as a capture, and what a hole is written with, is
// moved as a reference alone: a capture's labels are its label's
// parameter's, and a hole is made after this pass.
Slot Slots::anchorKey(const FlowAnchor &anchor) const {
  std::optional<Type> carrier = std::visit(
      llvm::makeVisitor(
          [](const FlowAnchor::Field &field) -> std::optional<Type> {
            return cast<DataType>(field.data).getCtor(field.ctor).fields[field.index];
          },
          [](const FlowAnchor::Elements &elements) -> std::optional<Type> {
            return elements.element;
          },
          [](const FlowAnchor::Forced &forced) -> std::optional<Type> {
            return cast<LazyType>(forced.lazy).getValue();
          },
          [](const FlowAnchor::Capture &) -> std::optional<Type> { return std::nullopt; },
          [](const FlowAnchor::Hole &) -> std::optional<Type> { return std::nullopt; }),
      anchor.place);
  if (!carrier || !carriesLabels(*carrier))
    return std::nullopt;
  return Key{unrestricted(*carrier), analysis.labelsOf(anchor)};
}

Slot Slots::keyOf(Value value) const {
  if (auto it = widened.find(value); it != widened.end())
    return it->second;
  return keyAt(FlowPoint::of(value));
}

Slot Slots::argumentKey(StringAttr fn, unsigned index) const {
  return signature(fn).arguments[index];
}

Slot Slots::resultKey(StringAttr fn, unsigned index) const { return signature(fn).results[index]; }

Slot Slots::fieldKey(DataType data, Tag tag, unsigned index) const {
  return anchorKey(FlowAnchor::fieldOf(data, tag, index));
}

Slot Slots::elementKey(Type element) const { return anchorKey(FlowAnchor::elementsOf(element)); }

Slot Slots::forcedKey(Type lazy) const {
  return anchorKey(FlowAnchor::forcedOf(unrestricted(lazy)));
}

const Signature &Slots::signature(StringAttr fn) const {
  auto it = signatures.find(fn);
  assert(it != signatures.end() && "every function of the program is keyed");
  return it->second;
}

// The parameters of `label` a closure or suspension of `carrier` holds:
// the leading ones, all but the closure type's arguments.
unsigned Slots::captures(StringAttr label, Type carrier) const {
  return signature(label).type.getNumInputs() - arity(carrier);
}

//===----------------------------------------------------------------------===//
// Every key the program may ask for
//===----------------------------------------------------------------------===//

void Slots::noteValue(Value value) {
  noteSlot(keyOf(value));
  noteType(value.getType());
}

// The slots a type holds that are not values: the fields of each data type
// met anywhere in it, a closure's or a suspension's signature included,
// and the elements of each shaped type in it. The remap looks into every
// type the program names, so every key it may ask for is noted here. The
// walker meets each type once over the whole decision, so a type shared by
// many others is looked into once.
void Slots::noteType(Type type) { types.walk(type); }

// A data type's body is not a part of the type to the walker, so its
// fields are walked from here.
void Slots::noteData(DataType data) {
  for (auto [tag, ctor] : llvm::zip_equal(data.getTags(), data.getCtors()))
    for (auto [i, field] : llvm::enumerate(ctor.fields)) {
      noteSlot(fieldKey(data, tag, static_cast<unsigned>(i)));
      noteType(field);
    }
}

// A slot's key, and the forced state a lazy key's cell holds once forced.
// A closure's captures are its label's parameters, whose keys every
// signature has noted.
void Slots::noteSlot(const Slot &slot) {
  if (!slot || !sums.insert({*slot, Sum()}).second)
    return;
  if (!slot->isLazy())
    return;
  noteSlot(forcedKey(slot->carrier));
  noteType(cast<LazyType>(slot->carrier).getValue());
}

//===----------------------------------------------------------------------===//
// The plan of one function
//===----------------------------------------------------------------------===//

// Read from the decision and the solve alone, for this function's own
// values, before its conversion starts: no other function is read, so the
// plans of several functions are made while others convert. Only a closure
// or a suspension changes its type in the conversion.
Plan Slots::plan(FuncOp fn) const {
  Plan out;
  auto add = [&](Value value) {
    Slot slot = keyOf(value);
    if (!slot)
      return;
    out.keys[value] = *slot;
    out.types[value] = typeOf(value.getType(), slot);
  };
  fn.walk([&](Operation *op) {
    for (Value result : op->getResults())
      add(result);
    for (Region &region : op->getRegions())
      for (Block &block : region)
        for (Value arg : block.getArguments())
          add(arg);
    for (OpOperand &use : op->getOpOperands())
      if (std::optional<FlowPoint> sink = analysis.sinkOf(use))
        if (Slot slot = keyAt(*sink))
          out.sinks[&use] = *slot;
  });
  return out;
}

} // namespace idr::defunctionalize
