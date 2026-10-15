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
  types.addWalk([this](ShapedType shaped) {
    Type element = shaped.getElementType();
    if (carriesLabels(element))
      noteKey(elementKey(element));
  });
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
    for (const Key &key : llvm::concat<const Key>(sig.arguments, sig.results))
      noteKey(key);
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
Key Slots::keyWith(Type carrier, const FlowPoint &point) const {
  if (!carriesLabels(carrier))
    return {};
  return {unrestricted(carrier), analysis.labelsOf(point)};
}

// The key of what is held at `point`. A parameter's and a result's are
// their function's, keyed once before anything else, so that no function
// is read while another converts; a part's is its anchor's.
Key Slots::keyAt(const FlowPoint &point) const {
  switch (point.kind) {
  case FlowPoint::Kind::Operand:
    return keyOf(point.operand->get());
  case FlowPoint::Kind::Value:
    return keyWith(point.value.getType(), point);
  case FlowPoint::Kind::Part:
    return anchorKey(point.anchor);
  case FlowPoint::Kind::Parameter:
    return argumentKey(point.function.getAttr(), point.index);
  case FlowPoint::Kind::Result:
    return resultKey(point.function.getAttr(), point.index);
  }
  llvm_unreachable("every kind of point is listed");
}

// The key of what every value of a kind holds at `anchor`. What a closure
// or a suspension holds as a capture, and what a hole is written with, is
// moved as a reference alone: a capture's labels are its label's
// parameter's, and a hole is made after this pass.
Key Slots::anchorKey(const FlowAnchor &anchor) const {
  Type carrier;
  switch (anchor.kind) {
  case FlowAnchor::Kind::Field:
    carrier = cast<DataType>(anchor.type).getCtor(anchor.ctor).fields[anchor.field];
    break;
  case FlowAnchor::Kind::Elements:
    carrier = anchor.type;
    break;
  case FlowAnchor::Kind::Forced:
    carrier = cast<LazyType>(anchor.type).getValue();
    break;
  case FlowAnchor::Kind::Capture:
  case FlowAnchor::Kind::Hole:
    return {};
  }
  if (!carriesLabels(carrier))
    return {};
  return {unrestricted(carrier), analysis.labelsOf(anchor)};
}

Key Slots::keyOf(Value value) const {
  if (auto it = widened.find(value); it != widened.end())
    return it->second;
  return keyAt(FlowPoint::of(value));
}

Key Slots::argumentKey(StringAttr fn, unsigned index) const {
  return signature(fn).arguments[index];
}

Key Slots::resultKey(StringAttr fn, unsigned index) const { return signature(fn).results[index]; }

Key Slots::fieldKey(DataType data, unsigned tag, unsigned index) const {
  return anchorKey(FlowAnchor::fieldOf(data, tag, index));
}

Key Slots::elementKey(Type element) const { return anchorKey(FlowAnchor::elementsOf(element)); }

Key Slots::forcedKey(Type lazy) const {
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
  if (carriesLabels(value.getType()))
    noteKey(keyOf(value));
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
  for (auto [tag, ctor] : llvm::enumerate(data.getCtors()))
    for (auto [i, field] : llvm::enumerate(ctor.fields)) {
      if (carriesLabels(field))
        noteKey(fieldKey(data, static_cast<unsigned>(tag), static_cast<unsigned>(i)));
      noteType(field);
    }
}

// A key, and the forced state a lazy key's cell holds once forced. A
// closure's captures are its label's parameters, whose keys every
// signature has noted.
void Slots::noteKey(const Key &key) {
  if (!key.first || !sums.insert({key, Sum()}).second)
    return;
  if (!isLazy(key))
    return;
  Type value = cast<LazyType>(key.first).getValue();
  if (carriesLabels(value))
    noteKey(forcedKey(key.first));
  noteType(value);
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
    if (!carriesLabels(value.getType()))
      return;
    Key key = keyOf(value);
    out.keys[value] = key;
    out.types[value] = typeOf(value.getType(), key);
  };
  fn.walk([&](Operation *op) {
    for (Value result : op->getResults())
      add(result);
    for (Region &region : op->getRegions())
      for (Block &block : region)
        for (Value arg : block.getArguments())
          add(arg);
    for (OpOperand &use : op->getOpOperands())
      if (carriesLabels(use.get().getType()))
        if (std::optional<FlowPoint> sink = analysis.sinkOf(use))
          out.sinks[&use] = keyAt(*sink);
  });
  return out;
}

} // namespace idr::defunctionalize
