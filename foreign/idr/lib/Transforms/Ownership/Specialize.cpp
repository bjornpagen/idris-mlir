// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A function specialized on the grade of its callers' values. A function
// called with exclusive values from some callers and shared ones from
// others would take its parameters shared, and test every cell for all of
// them. Instead it is specialized on the grade, as the specializer
// specializes on types: the calls whose every followed argument is
// exclusive go to a copy of their own, whose parameters the next solve
// proves exclusive. A call is redirected at most once, so the rounds end.
// A function whose callers the solver does not all see (a closure's code)
// keeps them, and a copy is never copied again.
#include "idr/Analysis/Ownership.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Ownership.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/SymbolTable.h"
#include "llvm/Support/Debug.h"

#define DEBUG_TYPE "idr-rc"

using namespace mlir;
using Sharing = idr::Exclusivity::Sharing;

namespace idr::ownership {

namespace {

// Whether the call gives every followed parameter an exclusive value, and
// at least one of them a value the function now takes shared.
bool improves(const Exclusivity &solved, FuncOp fn, CallOp call) {
  bool gains = false;
  for (auto [param, arg] : llvm::zip(fn.getArguments(), call.getArgOperands())) {
    if (!followed(param))
      continue;
    if (solved.of(arg) != Sharing::Exclusive)
      return false;
    gains |= solved.of(param) == Sharing::Shared;
  }
  return gains;
}

// The copy of `fn`, made on first need right after it. It keeps every fact
// of its original (its instance with them) but the clone, which names the
// original's key and nothing after idr-rc reads. The table renames it if
// the name is taken.
FuncOp copyOf(FuncOp fn, SymbolTable &symbols, Copies &copies) {
  if (FuncOp copy = copies.of.lookup(fn))
    return copy;
  FuncOp copy = fn.clone();
  copy.setSymName((fn.getSymName() + ".excl").str());
  copy.setPrivate();
  copy.removeCloneAttr();
  symbols.insert(copy, std::next(fn->getIterator()));
  copies.of.insert({fn, copy});
  copies.copies.insert(copy);
  return copy;
}

} // namespace

bool specializeOnGrade(ModuleOp module, const Exclusivity &solved, SymbolTable &symbols,
                       Copies &copies) {
  SmallVector<FuncOp> fns(module.getOps<FuncOp>());
  bool redirected = false;
  for (FuncOp fn : fns) {
    if (fn.isExternal() || fn.isPublic() || copies.copies.contains(fn))
      continue;
    std::optional<ArrayRef<Operation *>> callers = solved.callers(fn);
    if (!callers)
      continue;
    SmallVector<CallOp> exclusiveCalls;
    bool mixed = false;
    for (Operation *pred : *callers) {
      auto call = dyn_cast<CallOp>(pred);
      if (!call || !solved.live(call->getBlock()))
        continue;
      if (improves(solved, fn, call))
        exclusiveCalls.push_back(call);
      else
        mixed = true;
    }
    if (exclusiveCalls.empty() || !mixed)
      continue;
    FuncOp copy = copyOf(fn, symbols, copies);
    // The copy has its original's effects, which the call's contain.
    for (CallOp call : exclusiveCalls)
      call.setCalleeAttr(FlatSymbolRefAttr::get(copy.getSymNameAttr()));
    LLVM_DEBUG(llvm::dbgs() << "idr-rc: " << exclusiveCalls.size() << " calls of @"
                            << fn.getSymName() << " go to @" << copy.getSymName() << "\n");
    redirected = true;
  }
  return redirected;
}

// A function every call of which went to its copy is unused. One map lists
// every symbol's users; asking per original walks the module once per copy.
void eraseUnusedOriginals(ModuleOp module, SymbolTable &symbols, const Copies &copies) {
  SymbolTableCollection collection;
  SymbolUserMap users(collection, module);
  for (auto [original, copy] : copies.of)
    if (users.useEmpty(original))
      symbols.erase(original);
}

} // namespace idr::ownership
