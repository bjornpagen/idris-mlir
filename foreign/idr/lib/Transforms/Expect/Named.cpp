// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The functions a property names. A test names the function the
// programmer wrote, by its symbol or by its Idris definition, and a
// property stated of it holds of every copy the passes made of it: a
// specialization, a raised copy, a copy made for a pass's own purpose.
// What a copy is a copy of is in the facts of its idr.func, never in its
// name: `instance` names the Idris definition, which every copy keeps,
// and `clone` the key of a specialization or a raising, which names the
// function it was copied from.

#include "idr/Transforms/Expect.h"

#include "idr/IR/IdrDialect.h"

#include "llvm/ADT/DenseSet.h"

using namespace mlir;

namespace idr::expect {

namespace {

// The function a clone's key names: a specialization its origin, a raised
// copy the callee whose result it applies.
StringAttr copiedFrom(CloneAttr clone) {
  Attribute key = clone.getKey();
  if (auto spec = dyn_cast<SpecKeyAttr>(key))
    return spec.getOrigin();
  if (auto apply = dyn_cast<KeyApplyAttr>(key))
    return apply.getCallee();
  return cast<KeyApplyFieldAttr>(key).getCallee();
}

} // namespace

// The chain of keys ends at a function the module no longer has, or at a
// function met before, which only a module written by hand can hold.
bool names(FunctionOpInterface fn, StringRef f, SymbolTable &symbols) {
  llvm::SmallDenseSet<Operation *> seen;
  Operation *at = fn;
  while (at && seen.insert(at).second) {
    if (SymbolTable::getSymbolName(at).getValue() == f)
      return true;
    auto func = dyn_cast<FuncOp>(at);
    if (!func)
      return false;
    if (InstanceAttr instance = func.getInstanceAttr(); instance && instance.getOrigin().getValue() == f)
      return true;
    CloneAttr clone = func.getCloneAttr();
    if (!clone)
      return false;
    StringAttr from = copiedFrom(clone);
    if (from.getValue() == f)
      return true;
    at = symbols.lookup(from);
  }
  return false;
}

SmallVector<FunctionOpInterface> named(ModuleOp module, SymbolTable &symbols, StringRef function,
                                       StringRef property) {
  SmallVector<FunctionOpInterface> functions;
  StringRef f = function.ltrim('@');
  if (f.empty()) {
    fail(module.getLoc(), property) << "no function named";
    return functions;
  }
  for (auto fn : module.getOps<FunctionOpInterface>())
    if (names(fn, f, symbols))
      functions.push_back(fn);
  if (functions.empty())
    fail(module.getLoc(), property) << "no function " << function << ", and no clone of it";
  return functions;
}

SmallVector<Operation *> rootsOf(ModuleOp module, SymbolTable &symbols, StringRef function,
                                 StringRef property) {
  SmallVector<Operation *> roots;
  if (function.empty()) {
    roots.push_back(module);
    return roots;
  }
  for (FunctionOpInterface fn : named(module, symbols, function, property))
    roots.push_back(fn);
  return roots;
}

} // namespace idr::expect
