// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Symbol lookup: from the table a pass holds, from the collection a
// symbol-use verifier is handed, or, for code MLIR calls with no table in
// hand, by a scan of the nearest symbol table's top level. A pass never
// scans: it holds the SymbolTable analysis, which answers in O(1). A hook
// with no table scans only at the few sites that run it once per op they
// rewrite, so its cost is bounded by the module's top level per call, and
// it keeps nothing a sibling could read. And the questions answered from a
// declaration once it is found.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"

#include "llvm/ADT/SmallPtrSet.h"
#include "llvm/ADT/TypeSwitch.h"

using namespace mlir;
using namespace idr;

FlatSymbolRefAttr idr::getSumName(Type type) {
  return TypeSwitch<Type, FlatSymbolRefAttr>(unrestricted(type))
      .Case<DataType, BoxType>([](auto sum) { return sum.getName(); })
      .Default([](Type) { return nullptr; });
}

DataOp idr::lookupData(SymbolTable &symbols, Type type) {
  FlatSymbolRefAttr name = getSumName(type);
  return name ? symbols.lookup<DataOp>(name.getAttr()) : nullptr;
}

CtorOp idr::lookupCtor(SymbolTable &symbols, SymbolRefAttr ctor) {
  if (ctor.getNestedReferences().size() != 1)
    return nullptr;
  return lookupCtor(symbols.lookup<DataOp>(ctor.getRootReference()), ctor.getLeafReference());
}

DataOp idr::lookupData(SymbolTableCollection &symbols, Operation *from, Type type) {
  FlatSymbolRefAttr name = getSumName(type);
  return name ? symbols.lookupNearestSymbolFrom<DataOp>(from, name) : nullptr;
}

// A declaration's constructors are few, and its own symbol table is never
// built: they are read in place.
CtorOp idr::lookupCtor(DataOp data, StringRef ctor) {
  if (!data)
    return nullptr;
  return dyn_cast_or_null<CtorOp>(SymbolTable::lookupSymbolIn(data, ctor));
}

DataOp idr::declarationOf(Operation *from, Type type) {
  FlatSymbolRefAttr name = getSumName(type);
  if (!name)
    return nullptr;
  return SymbolTable::lookupNearestSymbolFrom<DataOp>(from, name.getAttr());
}

CtorOp idr::constructorOf(Operation *from, SymbolRefAttr ctor) {
  if (ctor.getNestedReferences().size() != 1)
    return nullptr;
  auto data = SymbolTable::lookupNearestSymbolFrom<DataOp>(from, ctor.getRootReference());
  return lookupCtor(data, ctor.getLeafReference());
}

Type idr::listElement(DataOp data) {
  if (!data)
    return {};
  for (CtorOp ctor : data.getBody().front().getOps<CtorOp>())
    if (ctor.getFieldTypes().size() == 2)
      return ctor.getFieldType(0);
  return {};
}

// The list is a box of two constructors, a nil without fields and a cons
// of an `element` and the list itself.
CtorOp idr::listCons(Operation *op, DataOp data, Type list, Type element) {
  CtorOp ctors[2];
  unsigned count = 0;
  if (data)
    for (CtorOp ctor : data.getBody().front().getOps<CtorOp>()) {
      if (count < 2)
        ctors[count] = ctor;
      ++count;
    }
  if (!isa<BoxType>(unrestricted(list)) || count != 2) {
    op->emitOpError("walks a list, a box of a nil and a cons, not ") << list;
    return nullptr;
  }
  CtorOp cons = ctors[0].getFieldTypes().size() == 2 ? ctors[0] : ctors[1];
  CtorOp nil = cons == ctors[0] ? ctors[1] : ctors[0];
  if (!nil.getFieldTypes().empty() || cons.getFieldTypes().size() != 2 ||
      cons.getFieldType(0) != element ||
      unrestricted(cons.getFieldType(1)) != unrestricted(list)) {
    op->emitOpError("walks a list of ") << element << ", not " << list;
    return nullptr;
  }
  return cons;
}

namespace {

// `visited`: the unboxed sums already asked about. Containment through
// them is acyclic, so one met again is one the verifier has yet to reject,
// or one whose answer is no (a yes ends the walk).
bool holds(Type type, function_ref<DataOp(Type)> declaration,
           llvm::SmallPtrSetImpl<Operation *> &visited) {
  // A linear value holds what the value it is holds: its quantity decides
  // only how it is used.
  type = unrestricted(type);
  if (isa<StrType, BigType, NatType, BoxType, FnType, LazyType, idr::TokenType>(type) ||
      isArray(type))
    return true;
  // An unboxed sum has no cell: it holds what its slots hold, which only
  // its declaration says, since the type is a name.
  if (!isa<DataType>(type))
    return false;
  DataOp decl = declaration(type);
  if (!decl || !visited.insert(decl).second)
    return false;
  for (CtorOp ctor : decl.getBody().front().getOps<CtorOp>())
    for (Type field : ctor.getFieldTypes().getAsValueRange<TypeAttr>())
      if (holds(field, declaration, visited))
        return true;
  return false;
}

} // namespace

bool idr::holdsReferences(Type type, function_ref<DataOp(Type)> declaration) {
  llvm::SmallPtrSet<Operation *, 4> visited;
  return holds(type, declaration, visited);
}

std::optional<idr::Elimination> idr::eliminationAt(OpOperand &use) {
  // The only user of `v`, if it has one.
  auto next = [](Value v) { return v.hasOneUse() ? *v.user_begin() : nullptr; };
  Elimination e;
  Value value = use.get();
  Operation *user = use.getOwner();
  if ((e.enter = dyn_cast<LinEnterOp>(user))) {
    e.exit = dyn_cast_or_null<LinUseOp>(next(e.enter.getResult()));
    if (!e.exit)
      return std::nullopt;
    user = next(value = e.exit.getResult());
  }
  if ((e.field = dyn_cast_or_null<FieldOp>(user)))
    user = next(value = e.field.getResult());
  if ((e.use = dyn_cast_or_null<LinUseOp>(user)))
    user = next(value = e.use.getResult());
  e.apply = dyn_cast_or_null<ApplyOp>(user);
  if (!e.apply || e.apply.getCallee() != value)
    return std::nullopt;
  return e;
}
