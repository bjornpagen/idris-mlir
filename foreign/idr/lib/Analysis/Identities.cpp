// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The functions of a component that give back an argument: the candidates,
// the walks, and the greatest fixpoint over them. IdentitiesRecord.cpp walks
// a function; IdentitiesRebuilds.cpp says why the assumptions that are left
// hold.
#include "idr/Analysis/Identities.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SetVector.h"

using namespace mlir;

namespace idr::identities {

SmallVector<unsigned, 1> candidates(FuncOp fn) {
  SmallVector<unsigned, 1> found;
  if (fn.getNumResults() != 1 || fn.getProgram().getStage() >= Stage::Owned)
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

Parts::Parts(Type argument) {
  parts.push_back({0, std::nullopt, 0, 0, unrestricted(argument)});
}

unsigned Parts::step(unsigned parent, std::optional<unsigned> tag, unsigned index, Type type) {
  auto [it, inserted] = steps.try_emplace(std::make_tuple(parent, tag, index),
                                          static_cast<unsigned>(parts.size()));
  if (inserted)
    parts.push_back({parent, tag, index, parts[parent].depth + 1, unrestricted(type)});
  return it->second;
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
      if (std::optional<unsigned> given = outside(callee).givesBack)
        assumed[callee] = {*given};
    });

  // One walk of each member with candidates; the fixpoint reads the walks
  // and does not walk a function again.
  struct Walked {
    std::optional<Record> record;
    // The members it calls, which an assumption about may decide its check.
    SmallVector<StringAttr> callees;
  };
  SmallVector<Walked, 0> walked(walkable.size());
  for (auto [slot, at] : llvm::enumerate(walkable)) {
    FuncOp fn = component[at];
    walked[slot].record.emplace(fn, assumed.find(fn.getSymNameAttr())->second, members, outside);
    fn.walk([&](CallOp call) {
      StringAttr callee = call.getCalleeAttr().getAttr();
      if (members.contains(callee))
        walked[slot].callees.push_back(callee);
    });
  }

  DenseMap<StringAttr, llvm::SetVector<unsigned>> callers;
  for (auto [slot, each] : llvm::enumerate(walked))
    for (StringAttr callee : each.callees)
      if (assumed.contains(callee))
        callers[callee].insert(static_cast<unsigned>(slot));

  // Assumptions are only ever dropped, so the worklist ends at the greatest
  // fixpoint.
  llvm::SetVector<unsigned> work;
  for (unsigned slot = 0, n = static_cast<unsigned>(walked.size()); slot < n; ++slot)
    work.insert(slot);
  while (!work.empty()) {
    unsigned slot = work.pop_back_val();
    StringAttr name = FuncOp(component[walkable[slot]]).getSymNameAttr();
    auto it = assumed.find(name);
    if (it == assumed.end())
      continue;
    SmallVector<unsigned, 1> kept = walked[slot].record->givesBack(it->second, assumed);
    if (kept.size() == it->second.size())
      continue;
    if (kept.empty())
      assumed.erase(it);
    else
      it->second = std::move(kept);
    if (auto calling = callers.find(name); calling != callers.end())
      for (unsigned caller : calling->second)
        work.insert(caller);
  }

  SmallVector<std::optional<unsigned>> out(component.size());
  for (unsigned at : walkable)
    if (auto it = assumed.find(FuncOp(component[at]).getSymNameAttr()); it != assumed.end())
      out[at] = it->second.front();
  return out;
}

} // namespace idr::identities
