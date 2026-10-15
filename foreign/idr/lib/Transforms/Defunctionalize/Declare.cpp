// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Every sum the conversion writes, made with its body before any function
// converts, and the types made anew once every function has. A closure sum
// has a constructor per label, of role Label, naming the label's function
// and holding its captures at their grades; a memo sum one per label,
// holding every parameter, `by_name` when the label's runs are observed,
// then its Running state and its Forced state, which holds the value. A
// capture that is a closure or a suspension is held as its key's sum, and
// any other as the type the program gave it: sums hold sums, which the
// definitions of one another tie, and a data type of the program that
// holds a slot is made anew after the conversion, with every type that
// holds it, a sum among them. Then each signature, each memo sum's dispatch
// function's, and each constant as its slots have it.

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

// The value of a sum held in a slot of `type`: a memo sum's cell is shared
// by every holder of it, so forcing one holder forces them all, and its
// value is always a box. Whether a closure sum is held in a box is decided
// for it as for every data type, by the cycles of the type graph, once
// every type is final.
Type held(Type type, bool lazy, DataType sum) {
  Type value = lazy ? Type(BoxType::get(sum)) : Type(sum);
  return isLinear(type) ? linear(value) : value;
}

} // namespace

Type Slots::sumOf(const Key &key) const { return typeOf(key.carrier, key); }

Type Slots::typeOf(Type type, const Slot &slot) const {
  if (!slot)
    return type;
  auto it = sums.find(*slot);
  assert(it != sums.end() && it->second.type && "every key of the program has a sum");
  return held(type, slot->isLazy(), it->second.type);
}

Tag Slots::labelTag(const Key &key, FlatSymbolRefAttr label) const {
  ArrayRef<Attribute> labels = key.labels.getValue();
  const Attribute *at = llvm::partition_point(labels, [&](Attribute one) {
    return cast<FlatSymbolRefAttr>(one).getValue() < label.getValue();
  });
  assert(at != labels.end() && *at == label && "a label of a slot is a label of its key");
  return Tag{static_cast<uint32_t>(at - labels.begin())};
}

FlatSymbolRefAttr Slots::forceOf(const Key &key) const {
  // Every lazy key of the program has a dispatch function.
  return forces.at(key);
}

LogicalResult Slots::declare(function_ref<bool(FuncOp)> byName) {
  if (failed(name()))
    return failure();
  for (auto &entry : sums)
    define(entry.first, byName);
  if (broken)
    return failure();
  for (auto &entry : signatures) {
    Signature &sig = entry.second;
    SmallVector<Type> inputs, results;
    for (auto [type, key] : llvm::zip_equal(sig.type.getInputs(), sig.arguments))
      inputs.push_back(typeOf(type, key));
    for (auto [type, key] : llvm::zip_equal(sig.type.getResults(), sig.results))
      results.push_back(typeOf(type, key));
    sig.converted = FunctionType::get(ctx, inputs, results);
  }
  // Each memo sum's dispatch function takes the cell and gives the value
  // its forced state holds. Its name is the sum's, which the key's content
  // made, and no Idris name holds the sum's `$`, so no function of the
  // program has it already.
  for (auto &[key, sum] : sums) {
    if (!key.isLazy())
      continue;
    auto name = StringAttr::get(ctx, sum.name.getValue() + ".force");
    if (signatures.count(name))
      return program.emitError("internal error: idr-defunctionalize: two dispatch functions "
                               "are named ")
             << name;
    Slot forced = forcedKey(key.carrier);
    Type cell = sumOf(key);
    Type value = typeOf(cast<LazyType>(key.carrier).getValue(), forced);
    Signature &sig = signatures[name];
    sig.converted = sig.type = FunctionType::get(ctx, ArrayRef<Type>(cell), ArrayRef<Type>(value));
    sig.arguments.push_back(std::nullopt);
    sig.results.push_back(forced);
    forces[key] = FlatSymbolRefAttr::get(name);
  }
  program.walk([&](ConstantOp constant) {
    Value result = constant.getResult();
    constants[constant] = convertConstant(constant.getValue(), keyOf(result));
  });
  return success();
}

// The sum of `key`, made the first time it is asked for. Its body may hold
// the sums of other keys, which are made in turn and may hold this one:
// `define` hands the body the type being made, which is kept before the
// body is, so that a sum asked for again while its body is made is that
// type.
DataType Slots::define(const Key &key, function_ref<bool(FuncOp)> byName) {
  Sum &sum = sums.find(key)->second;
  if (sum.type)
    return sum.type;
  // The fields of the body, which outlive the callback that hands it over.
  SmallVector<SmallVector<Type>> fields;
  FailureOr<DataType> made = DataType::define(ctx, sum.name.getValue(), [&](DataType self) {
    sum.type = self;
    return body(key, byName, fields);
  });
  if (failed(made))
    broken = true;
  sum.type = succeeded(made) ? *made : DataType();
  return sum.type;
}

// The type of a capture or forced value of type `type` held in `slot`: its
// key's sum, or, in a slot of no key, the type itself.
Type Slots::slotType(Type type, const Slot &slot, function_ref<bool(FuncOp)> byName) {
  if (!slot)
    return type;
  return held(type, slot->isLazy(), define(*slot, byName));
}

// The body of `key`'s sum: its labels in name order, then a memo sum's
// states; `fields` holds their field types.
DataType::Body Slots::body(const Key &key, function_ref<bool(FuncOp)> byName,
                           SmallVectorImpl<SmallVector<Type>> &fields) {
  bool lazy = key.isLazy();
  ArrayRef<Attribute> labels = key.labels.getValue();
  fields.resize(labels.size() + (lazy ? 2 : 0));
  for (auto [at, attr] : llvm::enumerate(labels)) {
    StringAttr label = cast<FlatSymbolRefAttr>(attr).getAttr();
    const Signature &sig = signature(label);
    for (unsigned i = 0, n = captures(label, key.carrier); i < n; ++i)
      fields[at].push_back(slotType(sig.type.getInput(i), sig.arguments[i], byName));
  }
  if (lazy) {
    Type value = cast<LazyType>(key.carrier).getValue();
    fields[labels.size() + 1].push_back(slotType(value, forcedKey(key.carrier), byName));
  }
  DataType::Body made;
  made.kind = lazy ? SumKind::Memo : SumKind::Closures;
  for (auto [at, attr] : llvm::enumerate(labels)) {
    auto label = cast<FlatSymbolRefAttr>(attr);
    made.ctors.push_back({label.getAttr(), fields[at],
                          lazy && byName(analysis.function(label.getAttr())), CtorRole::Label,
                          label});
  }
  if (lazy) {
    made.ctors.push_back({StringAttr::get(ctx, memoRunning), fields[labels.size()], false,
                          CtorRole::Running, FlatSymbolRefAttr()});
    made.ctors.push_back({StringAttr::get(ctx, memoForced), fields[labels.size() + 1], false,
                          CtorRole::Forced, FlatSymbolRefAttr()});
  }
  return made;
}

// A closure or suspension in a body is a field's slot, keyed by the
// field's anchor; one inside a shaped type is an element's, keyed by its
// element type's. Any other is a value's, which the conversion has given
// its slot's type already.
LogicalResult Slots::remake() {
  FailureOr<std::unique_ptr<DataRemap>> remap = DataRemap::create(
      program, "defun",
      [this](Type type, std::optional<DataRemap::FieldPlace> place) -> std::optional<Type> {
        if (place)
          if (Slot slot = fieldKey(place->owner, place->tag, place->field))
            return typeOf(type, slot);
        auto shaped = dyn_cast<ShapedType>(unrestricted(type));
        if (!shaped || !carriesLabels(shaped.getElementType()))
          return std::nullopt;
        Type element = shaped.getElementType();
        return graded(gradeOf(type), shaped.clone(typeOf(element, elementKey(element))));
      });
  if (failed(remap))
    return failure();
  (*remap)->retype(program);
  return success();
}

// The constant `attr`, held in `slot`, with each closure and suspension in
// it the constructor of its label in its slot's sum: a closure is held in
// a slot of a key. A constructor of the program's types stays of its type,
// which the remap makes anew with the rest. A shared part in one slot is
// converted once.
Attribute Slots::convertConstant(Attribute attr, const Slot &slot) {
  if (!holding.holds(attr))
    return attr;
  if (auto it = convertedParts.find({attr, slot}); it != convertedParts.end())
    return it->second;
  Attribute result;
  if (auto closure = dyn_cast<ClosureAttr>(attr)) {
    FlatSymbolRefAttr label = closure.getCallee();
    const Signature &sig = signature(label.getAttr());
    SmallVector<Attribute> captures;
    for (auto [i, capture] : llvm::enumerate(closure.getCaptures()))
      captures.push_back(convertConstant(capture, sig.arguments[i]));
    result = ConAttr::get(ctx, sums.find(*slot)->second.type, labelTag(*slot, label),
                          ArrayAttr::get(ctx, captures));
  } else {
    auto con = cast<ConAttr>(attr);
    DataType data = con.getData();
    Tag tag = con.getTag();
    auto field = [&](Attribute value, unsigned i) {
      return convertConstant(value, fieldKey(data, tag, i));
    };
    auto cell = [&](ArrayAttr fields, function_ref<unsigned(unsigned)> index) {
      SmallVector<Attribute> out;
      for (auto [i, value] : llvm::enumerate(fields))
        out.push_back(field(value, index(static_cast<unsigned>(i))));
      return ArrayAttr::get(ctx, out);
    };
    if (!con.isRun()) {
      result = ConAttr::get(ctx, data, tag, cell(con.getFields(), [](unsigned i) { return i; }));
    } else {
      // A run is converted cell by cell, its tail in the last cell's spine.
      unsigned spine = con.getSpine();
      SmallVector<ArrayAttr> cells;
      for (ArrayAttr one : con.getRunCells())
        cells.push_back(cell(one, [&](unsigned i) { return cellField(i, spine); }));
      result = ConAttr::getRun(ctx, data, tag, spine, cells, field(con.getTail(), spine));
    }
  }
  convertedParts[{attr, slot}] = result;
  return result;
}

} // namespace idr::defunctionalize
