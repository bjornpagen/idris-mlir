// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The clones of a module by key.
//
// A clone carries its key in its clone fact, which names the clone too, so
// that the next run shares it; parameter p holds hole p of the key. The
// table is the facts read once: one attribute per function, no body, no
// symbol resolved, so it is read serially rather than split per function.
// Two functions whose facts carry one key: the first in module order is the
// clone, the second only a function.
#include "idr/Analysis/Specialize.h"

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/SymbolTable.h"

using namespace mlir;

namespace idr {

CloneTable::Kind CloneTable::kindOf(Attribute key) {
  return isa<SpecKeyAttr>(key) ? Kind::Spec : Kind::Raise;
}

CloneTable::CloneTable(Operation *op, AnalysisManager &) {
  auto module = cast<ModuleOp>(op);
  for (auto fn : module.getOps<idr::FuncOp>()) {
    CloneAttr clone = fn.getCloneAttr();
    if (!clone)
      continue;
    StringAttr name = fn.getSymNameAttr();
    keys.try_emplace(name, clone.getKey());
    byKey.try_emplace(clone.getKey(), Clone{fn, clone.getKey(), FlatSymbolRefAttr::get(name),
                                            fn.getFunctionType(), fn.getEffects()});
  }
  // A raised clone counts for its callee's owner, which the first loop must
  // have recorded whatever the order of the two in the module.
  for (auto fn : module.getOps<idr::FuncOp>())
    if (const Clone *clone = find(fn.getSymNameAttr()))
      countFor(clone->key);
}

bool CloneTable::isInvalidated(const AnalysisManager::PreservedAnalyses &pa) const {
  return !pa.isPreserved<CloneTable>() || !pa.isPreserved<SymbolTable>();
}

const Clone *CloneTable::lookup(Attribute key) const {
  auto it = byKey.find(key);
  return it == byKey.end() ? nullptr : &it->second;
}

const Clone *CloneTable::find(StringAttr fn) const {
  Attribute key = keys.lookup(fn);
  const Clone *clone = key ? lookup(key) : nullptr;
  return clone && clone->name.getAttr() == fn ? clone : nullptr;
}

const Clone *CloneTable::specialization(StringAttr fn) const {
  const Clone *clone = find(fn);
  return clone && kindOf(clone->key) == Kind::Spec ? clone : nullptr;
}

StringAttr CloneTable::ownerOf(StringAttr fn) const {
  if (const Clone *clone = specialization(fn))
    return cast<SpecKeyAttr>(clone->key).getOrigin();
  return fn;
}

unsigned CloneTable::count(StringAttr owner) const {
  auto it = counts.find(owner);
  return it == counts.end() ? 0 : it->second[0] + it->second[1];
}

unsigned CloneTable::count(StringAttr owner, Kind kind) const {
  auto it = counts.find(owner);
  return it == counts.end() ? 0 : it->second[static_cast<unsigned>(kind)];
}

const Clone &CloneTable::add(idr::FuncOp fn) {
  Attribute key = fn.getCloneAttr().getKey();
  StringAttr name = fn.getSymNameAttr();
  keys[name] = key;
  const Clone &clone =
      byKey
          .insert_or_assign(key, Clone{fn, key, FlatSymbolRefAttr::get(name),
                                       fn.getFunctionType(), fn.getEffects()})
          .first->second;
  countFor(key);
  return clone;
}

// A specialization is its origin's; a raised clone, whose parameters are
// not its callee's, is counted with the clones of its callee's owner.
StringAttr CloneTable::ownerOfKey(Attribute key) const {
  if (auto spec = dyn_cast<SpecKeyAttr>(key))
    return spec.getOrigin();
  if (auto apply = dyn_cast<KeyApplyAttr>(key))
    return ownerOf(apply.getCallee());
  return ownerOf(cast<KeyApplyFieldAttr>(key).getCallee());
}

void CloneTable::countFor(Attribute key) {
  ++counts[ownerOfKey(key)][static_cast<unsigned>(kindOf(key))];
}

} // namespace idr
