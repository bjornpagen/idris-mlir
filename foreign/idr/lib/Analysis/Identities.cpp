// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The functions of a component that give back an argument: the candidates,
// the walks, and the greatest fixpoint over them. IdentitiesRecord.cpp walks
// a function; IdentitiesRebuilds.cpp says why the assumptions that are left
// hold.
#include "idr/Analysis/Identities.h"

#include "idr/IR/Func.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Worklist.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SetVector.h"

#include <optional>
#include <utility>

using namespace mlir;

namespace idr::identities {

SmallVector<unsigned, 1> candidates(FuncOp fn) {
  SmallVector<unsigned, 1> found;
  if (fn.getNumResults() != 1 || stageFacts(fn.getProgram().getStage()).counted())
    return found;
  ArrayRef<Type> arguments = fn.getArgumentTypes();
  Type result = fn.getResultTypes().front();
  if (llvm::any_of(arguments, [](Type type) { return isWorld(type); }))
    return found;
  for (auto [index, type] : llvm::enumerate(arguments))
    if (unrestricted(type) == unrestricted(result))
      found.push_back(static_cast<unsigned>(index));
  return found;
}

SmallVector<std::optional<unsigned>> givesBackOf(ArrayRef<FuncOp> component, Outside outside) {
  Members members;
  for (FuncOp fn : component)
    members[fn.getSymNameAttr()] = fn;

  // The members' candidates, then what each callee outside the component
  // gives back, which no drop below ever touches: it is final.
  Assumed assumed;
  SmallVector<unsigned> walkable;
  for (auto [at, each] : llvm::enumerate(component)) {
    FuncOp fn = each;
    SmallVector<unsigned, 1> cands = candidates(fn);
    if (cands.empty())
      continue;
    assumed[fn.getSymNameAttr()] = std::move(cands);
    walkable.push_back(static_cast<unsigned>(at));
  }
  for (unsigned at : walkable)
    FuncOp(component[at]).walk([&](CallOp call) {
      StringAttr callee = call.getCalleeAttr().getAttr();
      if (members.contains(callee) || assumed.contains(callee))
        return;
      if (std::optional<unsigned> given = outside(callee))
        assumed[callee] = {*given};
    });

  // One walk of each member with candidates, none for one that can give
  // nothing back; the fixpoint reads the walks and does not walk a
  // function again.
  struct Walked {
    StringAttr name;
    std::optional<Record> record;
    // The members it calls, which an assumption about may decide its check.
    SmallVector<StringAttr> callees;
  };
  SmallVector<Walked, 0> walked;
  for (unsigned at : walkable) {
    FuncOp fn = component[at];
    Walked &each = walked.emplace_back();
    each.name = fn.getSymNameAttr();
    each.record = Record::walk(fn, assumed.find(each.name)->second);
    fn.walk([&](CallOp call) {
      StringAttr callee = call.getCalleeAttr().getAttr();
      if (members.contains(callee))
        each.callees.push_back(callee);
    });
  }

  DenseMap<StringAttr, llvm::SetVector<unsigned>> callers;
  for (auto [slot, each] : llvm::enumerate(walked))
    for (StringAttr callee : each.callees)
      if (assumed.contains(callee))
        callers[callee].insert(static_cast<unsigned>(slot));

  // An assumption dropped: the walked member that no longer gives back an
  // argument. Each is dropped once and there are finitely many, so the
  // worklist ends, at the greatest fixpoint; a drop checks again each
  // member that calls the one it is about.
  using Drop = std::pair<unsigned, unsigned>;
  OnceWorklist<Drop> drops;
  auto check = [&](unsigned slot) {
    auto it = assumed.find(walked[slot].name);
    if (it == assumed.end())
      return;
    const std::optional<Record> &record = walked[slot].record;
    SmallVector<unsigned, 1> kept =
        record ? record->givesBack(it->second, assumed) : SmallVector<unsigned, 1>();
    if (kept.size() == it->second.size())
      return;
    for (unsigned argument : it->second)
      if (!llvm::is_contained(kept, argument))
        drops.push({slot, argument});
    if (kept.empty())
      assumed.erase(it);
    else
      it->second = std::move(kept);
  };
  for (unsigned slot = 0, n = static_cast<unsigned>(walked.size()); slot < n; ++slot)
    check(slot);
  while (std::optional<Drop> drop = drops.pop())
    if (auto calling = callers.find(walked[drop->first].name); calling != callers.end())
      for (unsigned caller : calling->second)
        check(caller);

  SmallVector<std::optional<unsigned>> out(component.size());
  for (unsigned at : walkable)
    if (auto it = assumed.find(FuncOp(component[at]).getSymNameAttr()); it != assumed.end())
      out[at] = it->second.front();
  return out;
}

} // namespace idr::identities
