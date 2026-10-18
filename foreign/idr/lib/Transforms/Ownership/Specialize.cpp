// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Functions specialized on the grade of their callers' values. A function
// called with exclusive values from some callers and shared ones from
// others would take its parameters shared, and test every cell for all of
// them. Instead it is specialized on the grade, as the specializer
// specializes on types: the calls whose every followed argument is
// exclusive go to a copy of their own, whose parameters are then
// exclusive. The copy's key is the function and the context it is made
// for, every followed parameter exclusive; one function has one such
// context, so one copy, made once and named from its key.
//
// The key set is decided before anything changes, on one solve: the
// functions some call gives exclusive values while another shares, and,
// since a copy calls what its original calls with values its own
// exclusive parameters may make exclusive, every function a key calls that
// takes a followed parameter shared. That set closes over a finite call
// graph, each function added once. The copies call what their originals
// call. One solve of the program with its copies then sends each call of
// a key or of its copy where it gives: to the copy when it gives exclusive
// values at every followed parameter, else to the original, deciding as it
// solves, so that a recursion stays in its copy (the recursive call passes
// on what the exclusive parameters were taken apart into) and a call fed
// by another copy's result gets that result exclusive. That solve is the
// program's once the calls went where it sent them, so the grades come
// from it. A function whose callers the solver does not all see, the root
// among them, keeps them. A copy no call kept, and an original every call
// of which went to its copy, is upstream's symbol-dce's, after this.
#include "idr/Analysis/Ownership.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"
#include "idr/Support/Worklist.h"
#include "idr/Transforms/Ownership.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/SymbolTable.h"
#include "llvm/Support/Debug.h"

#include <string>

#define DEBUG_TYPE "idr-rc-exclusive"

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

// The calls of `fn`, when the solve sees every one and `fn` takes a
// followed parameter shared: a copy could take that parameter exclusive.
// None otherwise.
std::optional<ArrayRef<CallOp>> copyable(const Exclusivity &solved, FuncOp fn) {
  std::optional<ArrayRef<CallOp>> callers = solved.callers(fn);
  if (callers && llvm::any_of(fn.getArguments(), [&](BlockArgument param) {
        return followed(param) && solved.of(param) == Sharing::Shared;
      }))
    return callers;
  return std::nullopt;
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

// A verified call names a function of the program.
FuncOp calleeOf(CallOp call, SymbolTable &symbols) {
  return symbols.lookup<FuncOp>(call.getCalleeAttr().getAttr());
}

} // namespace

FailureOr<Copies> specializeOnGrade(ProgramOp program, const Exclusivity &solved,
                                    SymbolTable &symbols) {
  // The keys some call asks for, found on the program as the solve saw it,
  // then the keys the copies ask for, each function once.
  OnceWorklist<FuncOp> keys;
  for (FuncOp fn : program.getOps<FuncOp>())
    if (std::optional<ArrayRef<CallOp>> callers = copyable(solved, fn);
        callers && llvm::any_of(*callers, [&](CallOp call) {
          return givesExclusive(solved, fn, call);
        }))
      (void)keys.push(fn);
  while (std::optional<FuncOp> key = keys.pop())
    key->walk([&](CallOp call) {
      if (FuncOp callee = calleeOf(call, symbols); copyable(solved, callee))
        (void)keys.push(callee);
    });

  // Each key's copy, right after its original. It keeps every fact of its
  // original. A name the table already holds is another key's: two keys
  // whose names meet are a collision, never a renamed copy.
  Copies copies;
  for (FuncOp fn : keys.entered()) {
    std::string name = copyName(fn);
    if (symbols.lookup(name))
      return fn.emitError("internal error: idr-rc-exclusive: the name @")
             << name << " of the exclusive copy of @" << fn.getSymName() << " is taken";
    FuncOp copy = fn.clone();
    copy.setSymName(name);
    symbols.insert(copy, std::next(fn->getIterator()));
    copies.of.insert({fn, copy});
  }
  LLVM_DEBUG(llvm::dbgs() << "idr-rc-exclusive: " << copies.of.size() << " exclusive copies\n");
  return copies;
}

void redirectCalls(ProgramOp program, const Exclusivity &solved) {
  // Found first and sent after: the calls are what the solve saw.
  SmallVector<std::pair<CallOp, FuncOp>> moves;
  program.walk([&](CallOp call) {
    std::optional<FuncOp> target = solved.target(call);
    if (target && target->getSymNameAttr() != call.getCalleeAttr().getAttr())
      moves.emplace_back(call, *target);
  });
  for (auto [call, target] : moves)
    call.setCalleeAttr(FlatSymbolRefAttr::get(target.getSymNameAttr()));
  LLVM_DEBUG(llvm::dbgs() << "idr-rc-exclusive: " << moves.size() << " calls redirected\n");
}

} // namespace idr::ownership
