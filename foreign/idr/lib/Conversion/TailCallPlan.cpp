// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The plan of idr-tail-calls, over the lowered module as it stands.

#include "idr/Conversion/Frame.h"
#include "idr/Conversion/ReturnRegisters.h"
#include "idr/Conversion/TailCallPlan.h"
#include "idr/Conversion/TailPosition.h"
#include "idr/Support/Worklist.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/IR/Threading.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SetVector.h"

#include <optional>
#include <utility>

using namespace mlir;

namespace idr::conversion {

namespace {

using ByName = DenseMap<StringAttr, LLVM::LLVMFuncOp>;

// The callee of `call` among `among`, or null.
LLVM::LLVMFuncOp calleeIn(LLVM::CallOp call, const ByName &among) {
  FlatSymbolRefAttr name = call.getCalleeAttr();
  return name ? among.lookup(name.getAttr()) : LLVM::LLVMFuncOp();
}

// The calls in tail position of one internal function, found from its body
// alone: those that leave its frame alone, and how many do not.
struct Candidates {
  SmallVector<LLVM::CallOp> calls;
  uint64_t frameBound = 0;
};

// What of a function the entry reaches once a return follows each of its
// planned tail calls: each block it reaches, with the last op of it that
// stays, the first planned call in it or else its terminator. The rest of
// a block after such a call is split off and reached by nothing.
using Reach = DenseMap<Block *, Operation *>;

Reach reach(LLVM::LLVMFuncOp fn, const DenseSet<Operation *> &planned) {
  Reach reached;
  // Each block enters once.
  OnceWorklist<Block *> work;
  work.push(&fn.getBody().front());
  while (std::optional<Block *> block = work.pop()) {
    auto first = llvm::find_if(**block, [&](Operation &op) { return planned.contains(&op); });
    if (first != (*block)->end()) {
      reached[*block] = &*first;
      continue;
    }
    reached[*block] = (*block)->getTerminator();
    for (Block *next : (*block)->getSuccessors())
      work.push(next);
  }
  return reached;
}

} // namespace

FailureOr<TailCallPlan> TailCallPlan::make(ModuleOp module, const CallCycles &cycles) {
  MLIRContext *ctx = module.getContext();
  TailCallPlan plan;

  // The functions only the module's calls reach.
  ByName internal;
  {
    SymbolTableCollection tables;
    SymbolUserMap users(tables, module);
    for (auto fn : module.getOps<LLVM::LLVMFuncOp>()) {
      if (fn.isExternal() || !fn.isPrivate() || fn.isVarArg())
        continue;
      StringAttr name = fn.getSymNameAttr();
      if (llvm::all_of(users.getUsers(fn), [&](Operation *user) {
            auto call = dyn_cast<LLVM::CallOp>(user);
            return call && call.getCalleeAttr() && call.getCalleeAttr().getAttr() == name;
          }))
        internal[name] = fn;
    }
  }

  // The calls in tail position among them that leave the caller's frame
  // alone, each function on its own.
  SmallVector<LLVM::LLVMFuncOp> callers;
  for (auto fn : module.getOps<LLVM::LLVMFuncOp>())
    if (internal.contains(fn.getSymNameAttr()))
      callers.push_back(fn);
  SmallVector<Candidates> found(callers.size());
  parallelFor(ctx, 0, callers.size(), [&](size_t i) {
    LLVM::LLVMFuncOp fn = callers[i];
    std::optional<Frame> frame;
    std::optional<TailPaths> paths;
    fn.walk([&](LLVM::CallOp call) {
      if (!calleeIn(call, internal))
        return;
      if (!paths)
        paths.emplace(fn);
      if (!paths->inTailPosition(call))
        return;
      if (!frame)
        frame.emplace(fn);
      if (frame->reachedBy(call)) {
        ++found[i].frameBound;
        return;
      }
      found[i].calls.push_back(call);
    });
  });

  // The callers and callees of candidates on one cycle take tailcc.
  for (auto [fn, candidates] : llvm::zip_equal(callers, found)) {
    plan.bound += candidates.frameBound;
    for (LLVM::CallOp call : candidates.calls) {
      LLVM::LLVMFuncOp callee = calleeIn(call, internal);
      if (!cycles.together(fn, callee))
        continue;
      plan.conventions[fn.getSymNameAttr()] = Convention::Tail;
      plan.conventions[callee.getSymNameAttr()] = Convention::Tail;
    }
  }
  // Each candidate between two of them is planned. The return right after
  // each planned call leaves the rest of its block, and what only that led
  // to, unreached: a planned call there is dropped.
  llvm::SetVector<Operation *> onTails;
  for (auto [fn, candidates] : llvm::zip_equal(callers, found)) {
    if (plan.conventionOf(fn.getSymNameAttr()) == Convention::C)
      continue;
    DenseSet<Operation *> planned;
    for (LLVM::CallOp call : candidates.calls)
      if (plan.conventionOf(call.getCalleeAttr().getAttr()) != Convention::C)
        planned.insert(call);
    if (planned.empty())
      continue;
    Reach kept = reach(fn, planned);
    for (LLVM::CallOp call : candidates.calls) {
      if (!planned.contains(call) || kept.lookup(call->getBlock()) != call)
        continue;
      plan.tailCalls[fn].push_back(call);
      onTails.insert(fn);
      onTails.insert(calleeIn(call, internal));
    }
  }

  // The results that do not fit the return registers go through memory, in
  // every function on a tail call, each of which takes tailcc already. The
  // machine is asked only when there is a result to measure.
  if (!onTails.empty()) {
    FailureOr<ReturnRegisters> registers = ReturnRegisters::of(module);
    if (failed(registers))
      return failure();
    for (Operation *on : onTails) {
      auto fn = cast<LLVM::LLVMFuncOp>(on);
      if (registers->fit(fn.getFunctionType().getReturnType()))
        continue;
      plan.conventions[fn.getSymNameAttr()] = Convention::TailThroughMemory;
      ++plan.memory;
    }
  }
  return plan;
}

Convention TailCallPlan::conventionOf(StringAttr callee) const {
  return conventions.lookup_or(callee, Convention::C);
}

ArrayRef<LLVM::CallOp> TailCallPlan::tailCallsOf(LLVM::LLVMFuncOp fn) const {
  auto planned = tailCalls.find(fn);
  return planned == tailCalls.end() ? ArrayRef<LLVM::CallOp>() : ArrayRef(planned->second);
}

} // namespace idr::conversion
