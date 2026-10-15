// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Functions specialized on the grade of their callers' values. A function
// called with exclusive values from some callers and shared ones from
// others would take its parameters shared, and test every cell for all of
// them. Instead it is specialized on the grade, as the specializer
// specializes on types: the calls whose every followed argument is
// exclusive go to a copy of their own, whose parameters the solve then
// proves exclusive. The copy's key is the function and the context it is
// made for, every followed parameter exclusive; one function has one such
// context, so one copy, made once and named from its key.
//
// The key set is decided before anything changes, on one solve: the
// functions some call gives exclusive values while another shares, and,
// since a copy calls what its original calls with values its own
// exclusive parameters may make exclusive, every function a key calls that
// takes a followed parameter shared. That set closes over a finite call
// graph, each function added once. The copies call one another as their
// originals do, which is what lets a recursion stay in its copy: the
// recursive call passes on what the exclusive parameters were taken apart
// into, and a call fed by another copy's result gets that result
// exclusive. One solve of the program with its copies then says where
// each call of a key or its copy goes: to the copy when it gives exclusive
// values at every followed parameter, else to the original; and if a call
// moved, the program is solved once more for the grades. A function whose
// callers the solver does not all see, the root among them, keeps them.
#include "idr/Analysis/Ownership.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"
#include "idr/Transforms/Ownership.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/SymbolTable.h"
#include "llvm/ADT/SetVector.h"
#include "llvm/Support/Debug.h"

#include <string>

#define DEBUG_TYPE "idr-rc"

using namespace mlir;
using Sharing = idr::Exclusivity::Sharing;

namespace idr::ownership {

namespace {

// Whether `call` gives every followed parameter of `fn` an exclusive value.
bool givesExclusive(const Exclusivity &solved, FuncOp fn, CallOp call) {
  for (auto [param, arg] : llvm::zip(fn.getArguments(), call.getArgOperands()))
    if (followed(param) && solved.of(arg) != Sharing::Exclusive)
      return false;
  return true;
}

// Whether `fn` takes a followed parameter shared, and the solve sees every
// call of it: a copy could take that parameter exclusive.
bool sharesAParameter(const Exclusivity &solved, FuncOp fn) {
  return solved.callers(fn) && llvm::any_of(fn.getArguments(), [&](BlockArgument param) {
           return followed(param) && solved.of(param) == Sharing::Shared;
         });
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

FuncOp calleeOf(CallOp call, SymbolTable &symbols) {
  return symbols.lookup<FuncOp>(call.getCalleeAttr().getAttr());
}

} // namespace

FailureOr<Copies> specializeOnGrade(ProgramOp program, const Exclusivity &solved,
                                    SymbolTable &symbols) {
  // The keys some call asks for, and those calls, found on the program as
  // the solve saw it.
  llvm::SetVector<FuncOp> keys;
  SmallVector<CallOp> exclusiveCalls;
  for (FuncOp fn : program.getOps<FuncOp>()) {
    if (!sharesAParameter(solved, fn))
      continue;
    for (Operation *pred : *solved.callers(fn)) {
      auto call = dyn_cast<CallOp>(pred);
      if (!call || !solved.live(call->getBlock()) || !givesExclusive(solved, fn, call))
        continue;
      exclusiveCalls.push_back(call);
      keys.insert(fn);
    }
  }
  // The keys the copies ask for.
  for (unsigned at = 0; at < keys.size(); ++at) {
    FuncOp key = keys[at];
    key.walk([&](CallOp call) {
      if (FuncOp callee = calleeOf(call, symbols); callee && sharesAParameter(solved, callee))
        keys.insert(callee);
    });
  }

  // Each key's copy, right after its original. It keeps every fact of its
  // original. A name the table already holds is another key's: two keys
  // whose names meet are a collision, never a renamed copy.
  Copies copies;
  for (FuncOp fn : keys) {
    std::string name = copyName(fn);
    if (symbols.lookup(name))
      return fn.emitError("idr-rc: internal error: the name @")
             << name << " of the exclusive copy of @" << fn.getSymName() << " is taken";
    FuncOp copy = fn.clone();
    copy.setSymName(name);
    symbols.insert(copy, std::next(fn->getIterator()));
    copies.of.insert({fn, copy});
  }
  auto toCopy = [&](CallOp call) {
    if (FuncOp copy = copies.of.lookup(calleeOf(call, symbols)))
      call.setCalleeAttr(FlatSymbolRefAttr::get(copy.getSymNameAttr()));
  };
  for (CallOp call : exclusiveCalls)
    toCopy(call);
  for (auto [original, copy] : copies.of)
    copy.walk(toCopy);
  LLVM_DEBUG(llvm::dbgs() << "idr-rc: " << copies.of.size() << " exclusive copies, "
                          << exclusiveCalls.size() << " calls of originals sent to them\n");
  return copies;
}

bool redirectCalls(ProgramOp program, const Exclusivity &solved, SymbolTable &symbols,
                   const Copies &copies) {
  // Each key and its copy, by either.
  DenseMap<Operation *, std::pair<FuncOp, FuncOp>> pairOf;
  for (auto [original, copy] : copies.of) {
    pairOf[original] = {cast<FuncOp>(original), copy};
    pairOf[copy] = {cast<FuncOp>(original), copy};
  }
  // Found first and sent after: the calls are what the solve saw.
  SmallVector<std::pair<CallOp, FuncOp>> moves;
  program.walk([&](CallOp call) {
    FuncOp callee = calleeOf(call, symbols);
    auto it = callee ? pairOf.find(callee) : pairOf.end();
    if (it == pairOf.end() || !solved.live(call->getBlock()))
      return;
    auto [original, copy] = it->second;
    FuncOp target = givesExclusive(solved, callee, call) ? copy : original;
    if (target != callee)
      moves.emplace_back(call, target);
  });
  for (auto [call, target] : moves)
    call.setCalleeAttr(FlatSymbolRefAttr::get(target.getSymNameAttr()));
  LLVM_DEBUG(llvm::dbgs() << "idr-rc: " << moves.size() << " calls redirected\n");
  return !moves.empty();
}

// What stays is what a function idr-rc left alone, or anything but a
// function, uses, and what that calls in turn, among the originals and the
// copies: a set that only grows within a finite one. A copy no call kept,
// with the copies only it called, goes, and so does an original every call
// of which went to its copy.
void eraseUnused(ProgramOp program, SymbolTable &symbols, const Copies &copies) {
  llvm::SetVector<Operation *> changed;
  for (auto [original, copy] : copies.of) {
    changed.insert(original);
    changed.insert(copy);
  }
  SymbolTableCollection collection;
  SymbolUserMap users(collection, program);
  llvm::SetVector<Operation *> kept;
  for (Operation *fn : changed)
    for (Operation *user : users.getUsers(fn)) {
      auto owner = user->getParentOfType<FuncOp>();
      if (!owner || !changed.contains(owner))
        kept.insert(fn);
    }
  for (unsigned at = 0; at < kept.size(); ++at)
    kept[at]->walk([&](CallOp call) {
      if (Operation *callee = symbols.lookup(call.getCalleeAttr().getAttr());
          callee && changed.contains(callee))
        kept.insert(callee);
    });
  for (Operation *fn : changed)
    if (!kept.contains(fn))
      symbols.erase(fn);
}

} // namespace idr::ownership
