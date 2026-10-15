// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Every type the conversion writes, made before any function converts:
// each key's sum by name, the data types whose bodies hold a slot remade
// with the slots' sums, then each sum's body, set once. A closure sum has a
// constructor per label, named by the label's function, holding its
// captures at their grades; a memo sum one per label, holding every
// parameter, `by_name` when the effects summary says its runs are
// observed, then `running` and `forced` with the value. Then each
// signature and each constant as its slots have it.

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

Type Slots::sumOf(const Key &key) const {
  auto it = sums.find(key);
  assert(it != sums.end() && it->second && "every key of the module has a sum");
  DataType sum = it->second;
  if (isLazy(key) || cyclic.contains(key))
    return BoxType::get(sum);
  return sum;
}

Type Slots::typeOf(Type type, const Key &key) const {
  if (!key.first)
    return mapped(type);
  Type sum = sumOf(key);
  return isLinear(type) ? linear(sum) : sum;
}

Type Slots::mapped(Type type) const {
  auto it = mappedTypes.find(type);
  return it == mappedTypes.end() ? type : it->second;
}

void Slots::remember(Type type) {
  if (!isKeyed(type))
    mappedTypes.try_emplace(type, remap->map(type));
}

LogicalResult Slots::declare(function_ref<bool(FuncOp)> byName) {
  if (failed(name()))
    return failure();
  // A closure or suspension in a body is a field's slot, keyed by the
  // field's anchor; one inside a shaped type is an element's, keyed by its
  // element type's. Any other is a value's, which the conversion keys by
  // its slot, and which the remap does not change.
  remap.emplace(
      module, "defun",
      [this](Type type, DataType owner, unsigned tag, unsigned field) -> std::optional<Type> {
        if (owner && isKeyed(type))
          return typeOf(type, fieldKey(owner, tag, field));
        auto shaped = dyn_cast<ShapedType>(unrestricted(type));
        if (!shaped || !isKeyed(shaped.getElementType()))
          return std::nullopt;
        Type element = shaped.getElementType();
        return graded(gradeOf(type), shaped.clone(typeOf(element, elementKey(element))));
      });
  if (failed(remap->status()))
    return failure();
  // Every type the decision and the conversion will ask the remap for: the
  // module's values' and signatures', and the parameters and forced values
  // the sums' bodies hold.
  module.walk([&](Operation *op) {
    for (Type type : op->getResultTypes())
      remember(type);
    for (Region &region : op->getRegions())
      for (Block &block : region)
        for (Type type : block.getArgumentTypes())
          remember(type);
  });
  for (auto &entry : signatures) {
    for (Type type : entry.second.type.getInputs())
      remember(type);
    for (Type type : entry.second.type.getResults())
      remember(type);
  }
  for (auto &entry : sums)
    if (isLazy(entry.first))
      remember(cast<LazyType>(entry.first.first).getValue());
  for (auto &entry : signatures) {
    Signature &sig = entry.second;
    SmallVector<Type> inputs, results;
    for (auto [type, key] : llvm::zip_equal(sig.type.getInputs(), sig.arguments))
      inputs.push_back(typeOf(type, key));
    for (auto [type, key] : llvm::zip_equal(sig.type.getResults(), sig.results))
      results.push_back(typeOf(type, key));
    sig.converted = FunctionType::get(ctx, inputs, results);
  }
  for (auto &[key, sum] : sums) {
    SmallVector<SmallVector<Type>> fields;
    SmallVector<Ctor> ctors = constructors(key, byName, fields);
    SumKind kind = isLazy(key) ? SumKind::Memo : SumKind::Closures;
    auto error = [&] { return module.emitError("internal error: idr-defunctionalize: "); };
    if (failed(sum.setBody(error, kind, ctors, InstanceAttr())))
      return failure();
  }
  module.walk([&](ConstantOp constant) {
    Value result = constant.getResult();
    constants[constant] = convertConstant(constant.getValue(), keyOf(result));
  });
  return success();
}

// The constructors of `key`'s sum, in tag order; `fields` holds their field
// types.
SmallVector<Ctor> Slots::constructors(const Key &key, function_ref<bool(FuncOp)> byName,
                                      SmallVectorImpl<SmallVector<Type>> &fields) const {
  bool lazy = isLazy(key);
  ArrayRef<Attribute> labels = key.second.getValue();
  fields.resize(labels.size() + (lazy ? 2 : 0));
  for (auto [at, attr] : llvm::enumerate(labels)) {
    StringAttr label = cast<FlatSymbolRefAttr>(attr).getAttr();
    const Signature &sig = signature(label);
    for (unsigned i = 0, n = captures(label, key.first); i < n; ++i)
      fields[at].push_back(typeOf(sig.type.getInput(i), sig.arguments[i]));
  }
  SmallVector<Ctor> ctors;
  for (auto [at, attr] : llvm::enumerate(labels)) {
    StringAttr label = cast<FlatSymbolRefAttr>(attr).getAttr();
    ctors.push_back({label, fields[at], lazy && byName(analysis.function(label))});
  }
  if (!lazy)
    return ctors;
  Type value = cast<LazyType>(key.first).getValue();
  fields[labels.size() + 1].push_back(typeOf(value, forcedKey(key.first)));
  ctors.push_back({StringAttr::get(ctx, memoRunning), fields[labels.size()], false});
  ctors.push_back({StringAttr::get(ctx, memoForced), fields[labels.size() + 1], false});
  return ctors;
}

// Whether a closure is inside `attr`, each part answered once.
bool Slots::holdsClosure(Attribute attr) {
  auto closure = dyn_cast<ClosureAttr>(attr);
  auto con = dyn_cast<ConAttr>(attr);
  if (!closure && !con)
    return false;
  if (auto it = holding.find(attr); it != holding.end())
    return it->second;
  bool found = static_cast<bool>(closure);
  if (con)
    eachField(con, [&](Attribute field, unsigned) { found = holdsClosure(field) || found; });
  holding[attr] = found;
  return found;
}

// The constant `attr`, held in a slot of `slot`, with each closure and
// suspension in it the constructor of its label in its slot's sum, and each
// constructor of a remade type one of the type it became. A shared part in
// one slot is converted once.
Attribute Slots::convertConstant(Attribute attr, const Key &slot) {
  auto con = dyn_cast<ConAttr>(attr);
  bool remade = con && dataTypeOf(remap->map(con.getData())) != con.getData();
  if (!remade && !holdsClosure(attr))
    return attr;
  if (auto it = convertedParts.find({attr, slot}); it != convertedParts.end())
    return it->second;
  Attribute result;
  if (auto closure = dyn_cast<ClosureAttr>(attr)) {
    StringAttr label = closure.getCallee().getAttr();
    const Signature &sig = signature(label);
    SmallVector<Attribute> captures;
    for (auto [i, capture] : llvm::enumerate(closure.getCaptures()))
      captures.push_back(convertConstant(capture, sig.arguments[i]));
    result = ConAttr::get(ctx, sums.lookup(slot), closure.getCallee(), ArrayAttr::get(ctx, captures));
  } else {
    DataType data = con.getData();
    DataType made = dataTypeOf(remap->map(data));
    std::optional<unsigned> tag = data.getTag(con.getCtor().getValue());
    assert(tag && "a constant's constructor is one of its type's");
    ArrayRef<Type> declared = data.getCtor(*tag).fields;
    auto field = [&](Attribute value, unsigned i) {
      return convertConstant(value, isKeyed(declared[i]) ? fieldKey(data, *tag, i) : Key());
    };
    auto cell = [&](ArrayAttr fields, function_ref<unsigned(unsigned)> index) {
      SmallVector<Attribute> out;
      for (auto [i, value] : llvm::enumerate(fields))
        out.push_back(field(value, index(static_cast<unsigned>(i))));
      return ArrayAttr::get(ctx, out);
    };
    if (!con.isRun()) {
      result = ConAttr::get(ctx, made, con.getCtor(),
                            cell(con.getFields(), [](unsigned i) { return i; }));
    } else {
      // A run is converted cell by cell, its tail in the last cell's spine.
      unsigned spine = con.getSpine();
      SmallVector<ArrayAttr> cells;
      for (ArrayAttr one : con.getRunCells())
        cells.push_back(cell(one, [&](unsigned i) { return cellField(i, spine); }));
      result =
          ConAttr::getRun(ctx, made, con.getCtor(), spine, cells, field(con.getTail(), spine));
    }
  }
  convertedParts[{attr, slot}] = result;
  return result;
}

} // namespace idr::defunctionalize
