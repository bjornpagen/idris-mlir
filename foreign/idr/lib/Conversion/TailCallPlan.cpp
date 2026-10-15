// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The plan of idr-tail-calls, over the lowered module as it stands.

#include "idr/Conversion/Frame.h"
#include "idr/Conversion/ReturnRegisters.h"
#include "idr/Conversion/TailCallPlan.h"
#include "idr/Conversion/TailPosition.h"
#include "idr/Support/Worklist.h"

#include "mlir/Analysis/CallGraph.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/IR/Threading.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/SCCIterator.h"
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

// Calls `each` with every call of `fn` that `reached` keeps, in program
// order.
void forEachCallKept(LLVM::LLVMFuncOp fn, const Reach &reached,
                     function_ref<void(LLVM::CallOp)> each) {
  for (Block &block : fn.getBody()) {
    auto last = reached.find(&block);
    if (last == reached.end())
      continue;
    for (Operation &op : llvm::make_range(block.begin(), std::next(last->second->getIterator())))
      op.walk([&](LLVM::CallOp call) { each(call); });
  }
}

} // namespace

FailureOr<TailCallPlan> TailCallPlan::make(ModuleOp module, const CallGraph &graph) {
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

  // The cycle of direct calls each function with a body is on, every one
  // of them a node of the graph.
  DenseMap<Operation *, unsigned> cycleOf;
  {
    unsigned index = 0;
    for (auto scc = llvm::scc_begin(&graph); !scc.isAtEnd(); ++scc, ++index)
      for (const CallGraphNode *node : *scc)
        if (!node->isExternal())
          cycleOf[node->getCallableRegion()->getParentOp()] = index;
  }

  // The callers and callees of candidates on a cycle take tailcc, and so do
  // their calls; each candidate between two of them is planned.
  ByName tail;
  for (auto [fn, candidates] : llvm::zip_equal(callers, found)) {
    plan.bound += candidates.frameBound;
    for (LLVM::CallOp call : candidates.calls) {
      LLVM::LLVMFuncOp callee = calleeIn(call, internal);
      if (cycleOf.at(fn) == cycleOf.at(callee)) {
        tail[fn.getSymNameAttr()] = fn;
        tail[callee.getSymNameAttr()] = callee;
      }
    }
  }
  // The return right after each planned call leaves the rest of its block,
  // and what only that led to, unreached: a planned call there is dropped.
  DenseMap<Operation *, Reach> reached;
  llvm::SetVector<Operation *> onTails;
  for (auto [fn, candidates] : llvm::zip_equal(callers, found)) {
    if (!tail.contains(fn.getSymNameAttr()))
      continue;
    DenseSet<Operation *> planned;
    for (LLVM::CallOp call : candidates.calls)
      if (calleeIn(call, tail))
        planned.insert(call);
    if (planned.empty())
      continue;
    const Reach &kept = reached[fn] = reach(fn, planned);
    for (LLVM::CallOp call : candidates.calls) {
      if (!planned.contains(call) || kept.lookup(call->getBlock()) != call)
        continue;
      plan.functions[fn].tailCalls.push_back(call);
      onTails.insert(fn);
      onTails.insert(calleeIn(call, tail));
    }
  }

  // The results that do not fit the return registers go through memory, in
  // every function on a tail call. A function that takes the pointer
  // returns nothing. The machine is asked only when there is a result to
  // measure.
  ByName inMemory;
  if (!onTails.empty()) {
    FailureOr<ReturnRegisters> registers = ReturnRegisters::of(module);
    if (failed(registers))
      return failure();
    for (Operation *on : onTails) {
      auto fn = cast<LLVM::LLVMFuncOp>(on);
      if (registers->fit(fn.getFunctionType().getReturnType()))
        continue;
      inMemory[fn.getSymNameAttr()] = fn;
      plan.functions[fn].resultInMemory = true;
    }
  }
  plan.memory = inMemory.size();

  for (const auto &[name, fn] : tail)
    plan.functions[fn].tail = true;
  for (auto fn : module.getOps<LLVM::LLVMFuncOp>()) {
    if (fn.isExternal())
      continue;
    fn.walk([&](LLVM::CallOp call) {
      if (calleeIn(call, tail))
        plan.functions[fn].tailccCalls.push_back(call);
    });
    if (inMemory.empty())
      continue;
    auto kept = reached.find(fn);
    if (kept == reached.end())
      kept = reached.try_emplace(fn, reach(fn, {})).first;
    forEachCallKept(fn, kept->second, [&](LLVM::CallOp call) {
      if (!calleeIn(call, inMemory) || llvm::is_contained(plan.functions[fn].tailCalls, call))
        return;
      plan.functions[fn].throughSlot.push_back(call);
    });
  }
  return plan;
}

const TailCallPlan::Function &TailCallPlan::of(LLVM::LLVMFuncOp fn) const {
  static const Function nothing;
  auto it = functions.find(fn);
  return it == functions.end() ? nothing : it->second;
}

} // namespace idr::conversion
