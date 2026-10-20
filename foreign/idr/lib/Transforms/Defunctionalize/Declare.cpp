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

// Every key of the program has its sum: decide made each before it
// returned the decision.
Type Slots::typeOf(Type type, const Slot &slot) const {
  if (!slot)
    return type;
  return held(type, slot->isLazy(), sums.at(*slot));
}

Tag Slots::labelTag(const Key &key, FlatSymbolRefAttr label) const {
  std::optional<unsigned> position = labels::positionIn(key.labels, label);
  assert(position && "a label of a slot is a label of its key");
  return Tag{*position};
}

FlatSymbolRefAttr Slots::forceOf(const Key &key) const {
  // Every lazy key of the program has a dispatch function.
  return forces.at(key);
}

// The parts in the order each reads the ones before it: the names, then
// each sum, which may hold the sums of later keys and makes them in turn,
// then the signatures and the dispatch functions' names, which read the
// sums, then the constants, which read both, and last the dispatch
// functions, born converted. The first failure is the decision's.
FailureOr<std::unique_ptr<Slots>> Slots::decide(ProgramOp program, Labels &labels,
                                                SymbolTable &symbols,
                                                function_ref<bool(FuncOp)> byName) {
  std::unique_ptr<Slots> slots(new Slots(program, labels, symbols));
  if (failed(slots->name()))
    return failure();
  for (const Key &key : slots->keys)
    if (failed(slots->define(key, byName)))
      return failure();
  slots->convertSignatures();
  if (failed(slots->nameForces()))
    return failure();
  program.walk([&](ConstantOp constant) {
    slots->constants[constant] = slots->convertConstant(constant.getValue(),
                                                        slots->keyOf(constant.getResult()));
  });
  for (const Key &key : slots->keys) {
    if (!key.isLazy())
      continue;
    FailureOr<FuncOp> dispatch = slots->defineForce(key, slots->sums.at(key));
    if (failed(dispatch))
      return failure();
    symbols.insert(*dispatch);
  }
  return slots;
}

void Slots::convertSignatures() {
  for (auto &entry : signatures) {
    Signature &sig = entry.second;
    SmallVector<Type> inputs, results;
    for (auto [type, key] : llvm::zip_equal(sig.type.getInputs(), sig.arguments))
      inputs.push_back(typeOf(type, key));
    for (auto [type, key] : llvm::zip_equal(sig.type.getResults(), sig.results))
      results.push_back(typeOf(type, key));
    sig.converted = FunctionType::get(ctx, inputs, results);
  }
}

// Each memo sum's dispatch function takes the cell and gives the value its
// forced state holds. Its name is the sum's, which the key's content made,
// and no Idris name holds the sum's `$`, so no function of the program has
// it already: two on one name are the compiler's error.
LogicalResult Slots::nameForces() {
  for (const Key &key : keys) {
    if (!key.isLazy())
      continue;
    auto name = StringAttr::get(ctx, names.at(key).getValue() + ".force");
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
  return success();
}

// The sum of `key`, made the first time it is asked for. Its body may hold
// the sums of other keys, which are made in turn and may hold this one:
// `define` hands the body the type being made, which is kept before the
// body is, so that a sum asked for again while its body is made is that
// type. A body that fails, here or in a sum it holds, is this sum's failure,
// returned to whatever asked for it.
FailureOr<DataType> Slots::define(const Key &key, function_ref<bool(FuncOp)> byName) {
  if (auto made = sums.find(key); made != sums.end())
    return made->second;
  // The fields of the body, which outlive the callback that hands it over.
  SmallVector<SmallVector<Type>> fields;
  return DataType::define(program, names.at(key).getValue(),
                          [&](DataType self) -> FailureOr<DataType::Body> {
                            sums[key] = self;
                            return body(key, byName, fields);
                          });
}

// The type of a capture or forced value of type `type` held in `slot`: its
// key's sum, or, in a slot of no key, the type itself.
FailureOr<Type> Slots::slotType(Type type, const Slot &slot, function_ref<bool(FuncOp)> byName) {
  if (!slot)
    return type;
  FailureOr<DataType> sum = define(*slot, byName);
  if (failed(sum))
    return failure();
  return held(type, slot->isLazy(), *sum);
}

// The body of `key`'s sum: its labels in name order, each naming its
// function, then a memo sum's states; `fields` holds their field types.
FailureOr<DataType::Body> Slots::body(const Key &key, function_ref<bool(FuncOp)> byName,
                                      SmallVectorImpl<SmallVector<Type>> &fields) {
  bool lazy = key.isLazy();
  ArrayRef<Attribute> labels = key.labels.getValue();
  fields.resize(labels.size() + (lazy ? 2 : 0));
  for (auto [at, attr] : llvm::enumerate(labels)) {
    StringAttr label = cast<FlatSymbolRefAttr>(attr).getAttr();
    const Signature &sig = signature(label);
    for (unsigned i = 0, n = captures(label, key.carrier); i < n; ++i) {
      FailureOr<Type> field = slotType(sig.type.getInput(i), sig.arguments[i], byName);
      if (failed(field))
        return failure();
      fields[at].push_back(*field);
    }
  }
  if (lazy) {
    Type value = cast<LazyType>(key.carrier).getValue();
    FailureOr<Type> field = slotType(value, forcedKey(key.carrier), byName);
    if (failed(field))
      return failure();
    fields[labels.size() + 1].push_back(*field);
  }
  DataType::Body made;
  made.kind = lazy ? SumKind::Memo : SumKind::Closures;
  for (auto [at, attr] : llvm::enumerate(labels)) {
    auto label = cast<FlatSymbolRefAttr>(attr);
    made.ctors.push_back(
        {label.getAttr(), fields[at],
         role::Label{label, lazy && byName(analysis.function(label.getAttr()))}});
  }
  if (lazy) {
    made.ctors.push_back(
        {StringAttr::get(ctx, memoRunning), fields[labels.size()], role::Running{}});
    made.ctors.push_back(
        {StringAttr::get(ctx, memoForced), fields[labels.size() + 1], role::Forced{}});
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
    result = ConAttr::get(ctx, sums.at(*slot), labelTag(*slot, label),
                          ArrayAttr::get(ctx, captures));
  } else {
    // A constructor's cells, each field converted in its slot, and the
    // constant made again of them: a plain constructor is one cell.
    auto con = cast<ConAttr>(attr);
    DataType data = con.getData();
    Tag tag = con.getTag();
    SmallVector<ArrayAttr> cells;
    for (auto [k, cell] : llvm::enumerate(con.getCells())) {
      SmallVector<Attribute> fields;
      for (auto [i, value] : llvm::enumerate(cell)) {
        unsigned field = con.fieldOfCell(static_cast<unsigned>(k), static_cast<unsigned>(i));
        fields.push_back(convertConstant(value, fieldKey(data, tag, field)));
      }
      cells.push_back(ArrayAttr::get(ctx, fields));
    }
    result = ConAttr::getRun(ctx, data, tag, con.getSpine(), cells);
  }
  convertedParts[{attr, slot}] = result;
  return result;
}

} // namespace idr::defunctionalize
