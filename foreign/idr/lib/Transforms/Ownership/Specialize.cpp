// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A function specialized on the grade of its callers' values. A function
// called with exclusive values from some callers and shared ones from
// others would take its parameters shared, and test every cell for all of
// them. Instead it is specialized on the grade, as the specializer
// specializes on types: the calls whose every followed argument is
// exclusive go to a copy of their own, whose parameters the next solve
// proves exclusive. The copy's key is the function and the context it is
// made for, every followed parameter exclusive; one function has one such
// context, so one copy, made once and named from its key. A function whose
// callers the solver does not all see keeps them, and a copy is never
// copied again.
#include "idr/Analysis/Ownership.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"
#include "idr/Transforms/Ownership.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/SymbolTable.h"
#include "llvm/Support/Debug.h"

#include <string>

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

// The copy's name, from its key: the original, and the positions of the
// parameters the copy takes exclusive, in order.
std::string copyName(FuncOp fn) {
  std::string key;
  for (BlockArgument param : fn.getArguments()) {
    if (!followed(param))
      continue;
    if (!key.empty())
      key += ',';
    key += std::to_string(param.getArgNumber());
  }
  return contentName(fn.getSymName(), "excl", key);
}

// The copy of `fn`, made on its key's first need, right after it. It keeps
// every fact of its original, its instance with them. A name the table
// already holds is another key's: two keys whose names meet are a
// collision, never a renamed copy.
FailureOr<FuncOp> copyOf(FuncOp fn, SymbolTable &symbols, Copies &copies) {
  if (FuncOp copy = copies.of.lookup(fn))
    return copy;
  std::string name = copyName(fn);
  if (symbols.lookup(name))
    return fn.emitError("idr-rc: internal error: the name @")
           << name << " of the exclusive copy of @" << fn.getSymName() << " is taken";
  FuncOp copy = fn.clone();
  copy.setSymName(name);
  copy.setPrivate();
  symbols.insert(copy, std::next(fn->getIterator()));
  copies.of.insert({fn, copy});
  copies.copies.insert(copy);
  return copy;
}

} // namespace

FailureOr<bool> specializeOnGrade(ModuleOp module, const Exclusivity &solved,
                                  SymbolTable &symbols, Copies &copies) {
  // The round's keys and the calls each takes, found on the module as the
  // solve saw it, before anything changes.
  SmallVector<std::pair<FuncOp, SmallVector<CallOp>>> keys;
  for (FuncOp fn : module.getOps<FuncOp>()) {
    if (fn.isPublic() || copies.copies.contains(fn))
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
    keys.emplace_back(fn, std::move(exclusiveCalls));
  }
  for (auto &[fn, calls] : keys) {
    FailureOr<FuncOp> copy = copyOf(fn, symbols, copies);
    if (failed(copy))
      return failure();
    // The copy has its original's effects, which the call's equal.
    for (CallOp call : calls)
      call.setCalleeAttr(FlatSymbolRefAttr::get(copy->getSymNameAttr()));
    LLVM_DEBUG(llvm::dbgs() << "idr-rc: " << calls.size() << " calls of @" << fn.getSymName()
                            << " go to @" << copy->getSymName() << "\n");
  }
  return !keys.empty();
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
