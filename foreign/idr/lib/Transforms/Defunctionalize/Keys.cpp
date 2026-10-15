// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The key of every slot (its carrier and the labels the solve found for
// it), every key the module may ask for, and the plan each function's
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
// then every key the module may ask for; then the cycles that box a key.
Slots::Slots(ModuleOp top, Labels &labels, SymbolTable &symbols)
    : module(top), analysis(labels), table(symbols), ctx(top.getContext()) {
  for (FuncOp fn : module.getOps<FuncOp>()) {
    Signature &sig = signatures[fn.getSymNameAttr()];
    sig.type = fn.getFunctionType();
    for (BlockArgument arg : fn.getArguments())
      sig.arguments.push_back(keyWith(arg.getType(), FlowPoint::of(Value(arg))));
    auto name = FlatSymbolRefAttr::get(fn.getSymNameAttr());
    for (auto [j, type] : llvm::enumerate(sig.type.getResults()))
      sig.results.push_back(keyWith(type, FlowPoint::result(name, static_cast<unsigned>(j))));
  }
  widen();
  for (FuncOp fn : module.getOps<FuncOp>()) {
    const Signature &sig = signatures.find(fn.getSymNameAttr())->second;
    for (auto [type, key] : llvm::zip_equal(sig.type.getInputs(), sig.arguments))
      key.first ? noteKey(key) : noteType(type);
    for (auto [type, key] : llvm::zip_equal(sig.type.getResults(), sig.results))
      key.first ? noteKey(key) : noteType(type);
    fn.walk([&](Operation *op) {
      for (Value result : op->getResults())
        noteValue(result);
      for (Region &region : op->getRegions())
        for (Block &block : region)
          for (Value arg : block.getArguments())
            noteValue(arg);
    });
  }
  decide();
}

// The key of a slot of `carrier` at `point`: none for a carrier that holds
// no label.
Key Slots::keyWith(Type carrier, const FlowPoint &point) const {
  if (!isKeyed(carrier))
    return {};
  return {unrestricted(carrier), analysis.labelsOf(point)};
}

// The key of what is held at `point`. A parameter's and a result's are
// their function's, keyed once before anything else, so that no function
// is read while another converts.
Key Slots::keyAt(const FlowPoint &point) const {
  switch (point.kind) {
  case FlowPoint::Kind::Operand:
    return keyOf(point.operand->get());
  case FlowPoint::Kind::Value:
    return keyWith(point.value.getType(), point);
  case FlowPoint::Kind::Parameter:
    return argumentKey(point.function.getAttr(), point.index);
  case FlowPoint::Kind::Result:
    return resultKey(point.function.getAttr(), point.index);
  case FlowPoint::Kind::Anchor:
    switch (point.anchor.kind) {
    case FlowAnchor::Kind::Field:
      return keyWith(
          cast<DataType>(point.anchor.type).getCtor(point.anchor.ctor).fields[point.anchor.field],
          point);
    case FlowAnchor::Kind::Elements:
      return keyWith(point.anchor.type, point);
    case FlowAnchor::Kind::Forced:
      return keyWith(cast<LazyType>(point.anchor.type).getValue(), point);
    }
  }
  llvm_unreachable("every kind of point is listed");
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
  return keyAt(FlowPoint::of(FlowAnchor::fieldOf(data, tag, index)));
}

Key Slots::elementKey(Type element) const {
  return keyAt(FlowPoint::of(FlowAnchor::elementsOf(element)));
}

Key Slots::forcedKey(Type lazy) const {
  return keyAt(FlowPoint::of(FlowAnchor::forcedOf(unrestricted(lazy))));
}

const Signature &Slots::signature(StringAttr fn) const {
  auto it = signatures.find(fn);
  assert(it != signatures.end() && "every function of the module is keyed");
  return it->second;
}

// The parameters of `label` a closure or suspension of `carrier` holds:
// the leading ones, all but the closure type's arguments.
unsigned Slots::captures(StringAttr label, Type carrier) const {
  return signature(label).type.getNumInputs() - arity(carrier);
}

//===----------------------------------------------------------------------===//
// Every key the module may ask for
//===----------------------------------------------------------------------===//

void Slots::noteValue(Value value) {
  if (isKeyed(value.getType()))
    return noteKey(keyOf(value));
  noteType(value.getType());
}

// The slots a type holds that are not values: the fields of each data type
// it names, transitively, and the elements of each shaped type in it.
void Slots::noteType(Type type) {
  type = unrestricted(type);
  if (auto box = dyn_cast<BoxType>(type))
    return noteType(box.getData());
  if (auto shaped = dyn_cast<ShapedType>(type)) {
    Type element = shaped.getElementType();
    return isKeyed(element) ? noteKey(elementKey(element)) : noteType(element);
  }
  auto data = dyn_cast<DataType>(type);
  if (!data || !data.hasBody() || !notedTypes.insert(data).second)
    return;
  for (auto [tag, ctor] : llvm::enumerate(data.getCtors()))
    for (auto [i, field] : llvm::enumerate(ctor.fields))
      isKeyed(field) ? noteKey(fieldKey(data, static_cast<unsigned>(tag), static_cast<unsigned>(i)))
                     : noteType(field);
}

// A key, and the keys its sum's body holds: a closure's captures, a
// suspension's parameters and the value its cell holds once forced.
void Slots::noteKey(const Key &key) {
  if (!key.first || !sums.insert({key, DataType()}).second)
    return;
  bool lazy = isLazy(key);
  for (auto label : key.second.getAsRange<FlatSymbolRefAttr>()) {
    const Signature &sig = signature(label.getAttr());
    for (unsigned i = 0, n = captures(label.getAttr(), key.first); i < n; ++i)
      sig.arguments[i].first ? noteKey(sig.arguments[i]) : noteType(sig.type.getInput(i));
  }
  if (!lazy)
    return;
  Type value = cast<LazyType>(key.first).getValue();
  isKeyed(value) ? noteKey(forcedKey(key.first)) : noteType(value);
}

//===----------------------------------------------------------------------===//
// The plan of one function
//===----------------------------------------------------------------------===//

// Read from the decision and the solve alone, for this function's own
// values, before its conversion starts: no other function is read, so the
// plans of several functions are made while others convert.
Plan Slots::plan(FuncOp fn) const {
  Plan out;
  auto add = [&](Value value) {
    if (isKeyed(value.getType())) {
      Key key = keyOf(value);
      out.keys[value] = key;
      out.types[value] = typeOf(value.getType(), key);
    } else {
      out.types[value] = mapped(value.getType());
    }
  };
  fn.walk([&](Operation *op) {
    for (Value result : op->getResults())
      add(result);
    for (Region &region : op->getRegions())
      for (Block &block : region)
        for (Value arg : block.getArguments())
          add(arg);
    for (OpOperand &use : op->getOpOperands())
      if (isKeyed(use.get().getType()))
        if (std::optional<FlowPoint> sink = analysis.sinkOf(use))
          out.sinks[&use] = keyAt(*sink);
  });
  return out;
}

} // namespace idr::defunctionalize
