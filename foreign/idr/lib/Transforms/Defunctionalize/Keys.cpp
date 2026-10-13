// The key of every slot that holds a closure or a suspension (its type and
// the labels the analysis found for it), in the order the module shows
// them, and the type each slot has once its key is decided.

#include "idr/IR/IdrDialect.h"
#include "idr/Analysis/Labels.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Symbols.h"
#include "idr/Transforms/Defunctionalize.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::defunctionalize {

// Every slot is keyed, values move between them, and the keys that become
// sums are decided, in this order: a field or an element is keyed before a
// value read from it, a value before a move of it, and the moves before the
// decision that reads them.
Slots::Slots(ModuleOp top, Labels &labels, SymbolTable &symbols)
    : module(top), analysis(labels), table(symbols), ctx(top.getContext()) {
  keyFields();
  keyArrays();
  keyFunctions();
  keyValues();
  widen();
  keyForces();
  order();
  connect();
  decide();
}

// The arguments a label of `type` is called with besides its captures: a
// closure's, or none, since every parameter of a suspended function is a
// capture.
unsigned Slots::arity(Type type) {
  auto fn = dyn_cast<FnType>(type);
  return fn ? static_cast<unsigned>(fn.getInputs().size()) : 0;
}

// Whether every label of `a` is one of `b`'s.
bool Slots::within(const Key &a, const Key &b) {
  return a.second && b.second && llvm::all_of(a.second, [&](Attribute label) {
           return llvm::is_contained(b.second, label);
         });
}

Key Slots::keyOf(Type type, const LabelSet &labels) const {
  Type carrier = unrestricted(type);
  if (labels.unknown)
    return {carrier, ArrayAttr()};
  return {carrier,
          ArrayAttr::get(ctx, SmallVector<Attribute>(labels.names.begin(), labels.names.end()))};
}

Key Slots::unknown(Type type) const { return {unrestricted(type), ArrayAttr()}; }

const Slots::Signature *Slots::signature(StringAttr fn) const {
  auto it = functions.find(fn);
  return it == functions.end() ? nullptr : &it->second;
}

Key Slots::argumentKey(StringAttr fn, unsigned index) const {
  const Signature *sig = signature(fn);
  return sig && index < sig->arguments.size() ? sig->arguments[index] : Key();
}

Key Slots::resultKey(StringAttr fn, unsigned index) const {
  const Signature *sig = signature(fn);
  return sig && index < sig->results.size() ? sig->results[index] : Key();
}

// Whether `label` is a function whose signature ends in `type`'s: the
// closure type's arguments and results, or for a suspension of a value,
// that value alone.
bool Slots::fits(StringAttr label, Type type) const {
  const Signature *sig = signature(label);
  if (!sig || sig->external)
    return false;
  ArrayRef<Type> inputs = sig->type.getInputs(), outputs = sig->type.getResults();
  if (auto lazy = dyn_cast<LazyType>(type))
    return outputs.size() == 1 && unrestricted(outputs[0]) == unrestricted(lazy.getValue());
  auto closure = cast<FnType>(type);
  return inputs.size() >= arity(type) &&
         llvm::equal(inputs.take_back(arity(type)), closure.getInputs()) &&
         llvm::equal(outputs, closure.getResults());
}

// The number of captures of `label` as a closure or suspension of `type`.
unsigned Slots::captures(StringAttr label, Type type) const {
  const Signature *sig = signature(label);
  return sig ? sig->type.getNumInputs() - arity(type) : 0;
}

// The slot of what a cell of lazy key `key` holds once forced: what its
// labels return, which is one slot when the key converts. Without a label,
// no function returns into it.
Key Slots::forced(const Key &key) const {
  Type value = cast<LazyType>(key.first).getValue();
  if (key.second && !key.second.empty())
    if (const Signature *sig = signature(cast<StringAttr>(key.second[0]));
        sig && sig->results.size() == 1)
      return sig->results[0];
  return isKeyed(value) ? keyOf(value, LabelSet{}) : Key();
}

Type Slots::typeOf(Type type, const Key &key) const {
  if (!key.first)
    return arrayed(type);
  Type slot = sumOf(key);
  if (!slot)
    slot = key.first;
  return isLinear(type) ? linear(slot) : slot;
}

Type Slots::typeOf(Value value) const {
  auto it = values.find(value);
  return it == values.end() ? arrayed(value.getType()) : typeOf(value.getType(), it->second);
}

// `type` with the element type of each array in it retyped by the key of
// its elements, at its grade. A type the conversion made is its own.
Type Slots::arrayed(Type type) const {
  auto array = dyn_cast<MemRefType>(unrestricted(type));
  if (!array || !isArray(array))
    return type;
  Type element = array.getElementType();
  Type now = typeOf(element, elementKey(element));
  if (now == element)
    return type;
  return graded(gradeOf(type), MemRefType::get(array.getShape(), now, array.getLayout(),
                                               array.getMemorySpace()));
}

FunctionType Slots::functionType(FuncOp fn) const {
  StringAttr name = fn.getSymNameAttr();
  FunctionType type = fn.getFunctionType();
  SmallVector<Type> inputs, results;
  for (auto [i, input] : llvm::enumerate(type.getInputs()))
    inputs.push_back(typeOf(input, argumentKey(name, static_cast<unsigned>(i))));
  for (auto [i, result] : llvm::enumerate(type.getResults()))
    results.push_back(typeOf(result, resultKey(name, static_cast<unsigned>(i))));
  return FunctionType::get(ctx, inputs, results);
}

SmallVector<Type> Slots::fieldTypes(CtorOp ctor) const {
  StringAttr data = ctor->getParentOfType<DataOp>().getSymNameAttr();
  SmallVector<Type> types;
  for (auto [i, type] : llvm::enumerate(ctor.getFieldTypes().getAsValueRange<TypeAttr>()))
    types.push_back(
        typeOf(type, fieldKey(data, ctor.getSymNameAttr(), static_cast<unsigned>(i))));
  return types;
}

SmallVector<Type> Slots::captureTypes(StringAttr label, const Key &key) const {
  SmallVector<Type> types;
  const Signature *sig = signature(label);
  if (!sig)
    return types;
  for (unsigned i = 0, n = captures(label, key.first); i < n; ++i)
    types.push_back(typeOf(sig->type.getInput(i), sig->arguments[i]));
  return types;
}

Type Slots::forcedType(const Key &key) const {
  return typeOf(cast<LazyType>(key.first).getValue(), forced(key));
}

void Slots::keyFields() {
  for (DataOp data : module.getOps<DataOp>())
    for (CtorOp ctor : data.getCtors()) {
      auto ref = SymbolRefAttr::get(data.getSymNameAttr(),
                                    {FlatSymbolRefAttr::get(ctor.getSymNameAttr())});
      for (auto [i, type] : llvm::enumerate(ctor.getFieldTypes().getAsValueRange<TypeAttr>()))
        if (isKeyed(type))
          fields[{data.getSymNameAttr(), ctor.getSymNameAttr(), unsigned(i)}] =
              keyOf(type, analysis.fieldLabels(ref, static_cast<unsigned>(i)));
    }
}

// Every element type of an array the module names anywhere, in a value, a
// signature or a field, nested in another array too.
void Slots::keyArrays() {
  auto scan = [&](Type type) {
    type.walk([&](MemRefType array) {
      Type element = array.getElementType();
      if (!isArray(array) || !isKeyed(element) || arrays.count(element))
        return;
      arrays[element] = keyOf(element, analysis.elementLabels(element));
    });
  };
  module->walk([&](Operation *op) {
    if (auto fn = dyn_cast<FuncOp>(op))
      scan(fn.getFunctionType());
    if (auto ctor = dyn_cast<CtorOp>(op))
      for (Type type : ctor.getFieldTypes().getAsValueRange<TypeAttr>())
        scan(type);
    for (Type type : op->getResultTypes())
      scan(type);
    for (Region &region : op->getRegions())
      for (Block &block : region)
        for (Type type : block.getArgumentTypes())
          scan(type);
  });
}

// The keys of each function's arguments and results. A function without a
// body may be given and may return anything.
void Slots::keyFunctions() {
  for (FuncOp fn : module.getOps<FuncOp>()) {
    Signature &sig = functions[fn.getSymNameAttr()];
    sig.type = fn.getFunctionType();
    sig.external = fn.isExternal();
    SmallVector<LabelSet> joined(sig.type.getNumResults());
    for (auto [i, type] : llvm::enumerate(sig.type.getInputs())) {
      if (!isKeyed(type)) {
        sig.arguments.push_back(Key());
      } else if (sig.external) {
        sig.arguments.push_back(unknown(type));
      } else {
        BlockArgument arg = fn.getArgument(static_cast<unsigned>(i));
        values[arg] = keyOf(type, analysis.labelsOf(arg));
        sig.arguments.push_back(values[arg]);
      }
    }
    if (sig.external)
      llvm::for_each(joined, [](LabelSet &labels) { labels.unknown = true; });
    // A function returns only from the terminators of its body's blocks.
    for (Block &block : fn.getBody())
      if (auto ret = dyn_cast<ReturnOp>(block.getTerminator()))
        for (auto [operand, labels] : llvm::zip_equal(ret.getOperands(), joined))
          labels = LabelSet::join(labels, analysis.labelsOf(operand));
    for (auto [type, labels] : llvm::zip(sig.type.getResults(), joined))
      sig.results.push_back(isKeyed(type) ? keyOf(type, labels) : Key());
  }
}

// The keys of values, from what the analysis found for each.
void Slots::keyValues() {
  module.walk([&](Operation *op) {
    auto match = dyn_cast<MatchOp>(op);
    auto fold = dyn_cast<ArrayFoldOp>(op);
    for (Region &region : op->getRegions())
      for (Block &block : region)
        for (BlockArgument arg : block.getArguments()) {
          if (!isKeyed(arg.getType()) || (isa<FuncOp>(op) && block.isEntryBlock()))
            continue;
          // The arguments of a case are the fields of its constructor, and
          // a fold's element is one of its array's.
          if (match) {
            auto ctor = cast<FlatSymbolRefAttr>(match.getCases()[region.getRegionNumber()]);
            values[arg] = fieldKey(getSumName(match.getScrutinee().getType()).getAttr(),
                                   ctor.getAttr(), arg.getArgNumber());
          } else if (fold && arg.getArgNumber() == 1) {
            values[arg] = elementKey(fold.getArrayType().getElementType());
          } else {
            values[arg] = keyOf(arg.getType(), analysis.labelsOf(arg));
          }
        }
    for (OpResult result : op->getResults()) {
      if (!isKeyed(result.getType()))
        continue;
      if (auto read = dyn_cast<FieldOp>(op)) {
        StringAttr data = getSumName(read.getValue().getType()).getAttr();
        values[result] = fieldKey(data, read.getCtorAttr().getAttr(),
                                  static_cast<unsigned>(read.getIndex()));
      } else if (auto get = dyn_cast<ArrayGetOp>(op)) {
        values[result] = elementKey(get.getArrayType().getElementType());
      } else {
        values[result] = keyOf(result.getType(), analysis.labelsOf(result));
      }
    }
  });
}

// A force's value is in the one slot its cell's labels return into, where
// the cell's labels are known: what the force gives is what the cell's
// `forced` state holds.
void Slots::keyForces() {
  module.walk([&](ForceOp force) {
    Key cell = values.lookup(force.getSuspension());
    if (isKeyed(force.getType()) && isLazy(cell) && cell.second)
      values[force.getResult()] = forced(cell);
  });
}

void Slots::note(const Key &key, Operation *at) {
  if (!key.first || !sums.insert({key, Type()}).second)
    return;
  firstSeen.try_emplace(key, at);
  // No label returns into the value of a cell no label reaches, so no
  // function notes its key.
  if (isLazy(key) && isEmpty(key))
    note(forced(key), at);
}

// The keys of the elements of every array in `type`.
void Slots::noteArrays(Type type, Operation *at) {
  type.walk([&](MemRefType array) { note(elementKey(array.getElementType()), at); });
}

// Every slot's key in the order the module shows it.
void Slots::order() {
  module->walk<WalkOrder::PreOrder>([&](Operation *op) {
    if (auto ctor = dyn_cast<CtorOp>(op)) {
      auto data = ctor->getParentOfType<DataOp>().getSymNameAttr();
      for (auto [i, type] : llvm::enumerate(ctor.getFieldTypes().getAsValueRange<TypeAttr>())) {
        note(fieldKey(data, ctor.getSymNameAttr(), static_cast<unsigned>(i)), op);
        noteArrays(type, op);
      }
      return;
    }
    if (auto fn = dyn_cast<FuncOp>(op)) {
      if (const Signature *sig = signature(fn.getSymNameAttr())) {
        for (const Key &key : sig->arguments)
          note(key, op);
        for (const Key &key : sig->results)
          note(key, op);
      }
      noteArrays(fn.getFunctionType(), op);
      return;
    }
    for (Value result : op->getResults()) {
      note(values.lookup(result), op);
      noteArrays(result.getType(), op);
    }
    for (Region &region : op->getRegions())
      for (Block &block : region)
        for (Value arg : block.getArguments()) {
          note(values.lookup(arg), op);
          noteArrays(arg.getType(), op);
        }
  });
}

} // namespace idr::defunctionalize
