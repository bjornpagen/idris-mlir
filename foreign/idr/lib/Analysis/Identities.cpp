// The functions that give back an argument: the candidates, the walks, and
// the greatest fixpoint over them. IdentitiesRecord.cpp walks a function;
// IdentitiesRebuilds.cpp says why the assumptions that are left hold.
#include "idr/Analysis/Identities.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/Threading.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SetVector.h"

using namespace mlir;

namespace idr {

bool Identities::owns(Type type) { return gradeOf(type).permission != Permission::Plain; }

SmallVector<unsigned, 1> Identities::candidates(FuncOp fn) {
  SmallVector<unsigned, 1> found;
  if (fn.isExternal() || fn.getNumResults() != 1)
    return found;
  ArrayRef<Type> arguments = fn.getArgumentTypes();
  Type result = fn.getResultTypes().front();
  if (owns(result) || llvm::any_of(arguments, owns) ||
      llvm::any_of(arguments, [](Type type) { return isWorld(type); }))
    return found;
  for (auto [index, type] : llvm::enumerate(arguments))
    if (unrestricted(type) == unrestricted(result))
      found.push_back(static_cast<unsigned>(index));
  return found;
}

Identities::Parts::Parts(Type argument) { parts.push_back({0, {}, 0, 0, unrestricted(argument)}); }

unsigned Identities::Parts::step(unsigned parent, StringAttr ctor, unsigned index, Type type) {
  auto [it, inserted] = steps.try_emplace(std::make_tuple(parent, ctor, index),
                                          static_cast<unsigned>(parts.size()));
  if (inserted)
    parts.push_back({parent, ctor, index, parts[parent].depth + 1, unrestricted(type)});
  return it->second;
}

Identities::Identities(Operation *op, AnalysisManager &am) {
  SymbolTable &symbols = am.getAnalysis<SymbolTable>();
  Assumed assumed;
  SmallVector<FuncOp> functions;
  for (FuncOp fn : cast<ModuleOp>(op).getOps<FuncOp>()) {
    SmallVector<unsigned, 1> found = candidates(fn);
    if (found.empty())
      continue;
    assumed[fn.getSymNameAttr()] = std::move(found);
    functions.push_back(fn);
  }

  // One walk of each function, all at once: each reads its own body, the
  // table and the declarations, and writes only its own slot. The fixpoint
  // reads the walks; it does not walk a function again.
  struct Walked {
    std::optional<Record> record;
    // The functions it calls, which an assumption about may decide its
    // check.
    SmallVector<StringAttr> callees;
  };
  SmallVector<Walked, 0> walked(functions.size());
  parallelFor(op->getContext(), 0, functions.size(), [&](size_t at) {
    FuncOp fn = functions[at];
    walked[at].record.emplace(fn, assumed.find(fn.getSymNameAttr())->second, symbols);
    fn.walk([&](CallOp call) { walked[at].callees.push_back(call.getCalleeAttr().getAttr()); });
  });

  DenseMap<StringAttr, llvm::SetVector<unsigned>> callers;
  for (auto [at, each] : llvm::enumerate(walked))
    for (StringAttr callee : each.callees)
      if (assumed.contains(callee))
        callers[callee].insert(static_cast<unsigned>(at));

  // Assumptions are only ever dropped, so the worklist ends at the greatest
  // fixpoint.
  llvm::SetVector<unsigned> work;
  for (unsigned at = 0, n = static_cast<unsigned>(functions.size()); at < n; ++at)
    work.insert(at);
  while (!work.empty()) {
    unsigned at = work.pop_back_val();
    StringAttr name = functions[at].getSymNameAttr();
    auto it = assumed.find(name);
    if (it == assumed.end())
      continue;
    SmallVector<unsigned, 1> kept = walked[at].record->givesBack(it->second, assumed);
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
  for (FuncOp fn : functions)
    if (auto it = assumed.find(fn.getSymNameAttr()); it != assumed.end())
      found[fn.getSymNameAttr()] = it->second.front();
}

bool Identities::isInvalidated(const AnalysisManager::PreservedAnalyses &pa) const {
  return !pa.isPreserved<Identities>() || !pa.isPreserved<SymbolTable>();
}

std::optional<unsigned> Identities::givesBack(StringAttr function) const {
  if (auto it = found.find(function); it != found.end())
    return it->second;
  return std::nullopt;
}

} // namespace idr
