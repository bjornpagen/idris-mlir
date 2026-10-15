// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-contify: a private idr.func whose one use is a call from another
// function on a cycle of calls with it becomes part of that function: its
// body moves into the call, with MLIR's inlineCall, and the function goes.
//
// This is MLton's contification (Fluet and Weeks, Contification Using
// Dominators) where a body of regions can hold it. A function with one
// call site always returns to the same place, its one predecessor
// dominates it, and moving its body there copies nothing. A second call
// site would need a branch out of a match region into a block they share,
// which a structured body cannot hold.
//
// Idris lifts every `case` and `if` on a clause's right-hand side into a
// function of its own, a case block, which its parent calls once and
// which often calls the parent back, as recursion through an `if` does.
// The ready set never inlines a member of a cycle, since its original
// could never go, so the parent and the case block would stay two
// functions, and a cell the parent takes apart could not be reused by the
// constructor the case block builds. A function on no cycle with its
// caller is left to the ready set, which inlines a function of one call
// within the caller's cap: moved here, before any cap, single calls would
// build the giant bodies the cap exists to prevent.
//
// The parent keeps Idris's proof of termination only if the case block had
// it too (FuncOp::absorb). Each move erases a function, so the pass ends;
// a move changes which functions are on a cycle together, so the cycles
// are taken anew for each sweep.

#include "idr/Transforms/Optimize.h"

#include "idr/Analysis/Holds.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/TypeGraph.h"
#include "idr/Support/Scc.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Transforms/Inliner.h"
#include "mlir/Transforms/InliningUtils.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

namespace idr {
#define GEN_PASS_DEF_IDRCONTIFY
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace {

// The component of the call graph each function is in, by its position in
// module order.
llvm::DenseMap<Operation *, unsigned> componentsOf(MutableArrayRef<idr::FuncOp> fns,
                                                    SymbolTable &symbols) {
  llvm::DenseMap<Operation *, unsigned> index;
  for (auto [at, fn] : llvm::enumerate(fns))
    index.try_emplace(fn, static_cast<unsigned>(at));
  SmallVector<SmallVector<unsigned>> successors(fns.size());
  for (auto [at, fn] : llvm::enumerate(fns)) {
    llvm::SmallDenseSet<unsigned, 8> seen;
    fn.getBody().walk<WalkOrder::PreOrder>([&](idr::CallOp call) {
      auto callee = symbols.lookup<idr::FuncOp>(call.getCalleeAttr().getAttr());
      auto found = callee ? index.find(callee) : index.end();
      if (found != index.end() && seen.insert(found->second).second)
        successors[at].push_back(found->second);
    });
  }
  llvm::DenseMap<Operation *, unsigned> component;
  for (auto [number, members] : llvm::enumerate(idr::components(successors)))
    for (unsigned at : members)
      component.try_emplace(fns[at], static_cast<unsigned>(number));
  return component;
}

// Whether `fn`'s body may take the place of `call`: a body of several
// blocks, or one that does not return to the call (it ends in
// ub.unreachable), goes in as blocks of its own, which a match region,
// holding one block, cannot take.
bool fitsRegion(InlinerInterface &interface, idr::CallOp call, idr::FuncOp fn) {
  Region &body = fn.getBody();
  bool needsBlocks =
      llvm::hasNItemsOrMore(body, /*N=*/2) || !interface.allowSingleBlockOptimization(body);
  if (!needsBlocks)
    return true;
  Operation *parent = call->getParentOp();
  return parent->getName() == fn->getName() || !parent->mightHaveTrait<OpTrait::SingleBlock>();
}

// Moves every function of one call from another member of its component
// into that call; how many.
unsigned contify(ModuleOp module, SymbolTable &symbols) {
  unsigned contified = 0;
  InlinerInterface interface(module.getContext());
  InlinerConfig config;
  for (bool changed = true; changed;) {
    changed = false;
    SmallVector<idr::FuncOp> fns(module.getOps<idr::FuncOp>());
    llvm::DenseMap<Operation *, unsigned> component = componentsOf(fns, symbols);
    // The users of every function as the sweep begins. A body moved into
    // its caller keeps its uses, now in the caller; the one call moved
    // goes with the function it named.
    SymbolTableCollection tables;
    SymbolUserMap users(tables, module);
    for (idr::FuncOp fn : fns) {
      if (!fn.isPrivate())
        continue;
      ArrayRef<Operation *> uses = users.getUsers(fn);
      if (uses.size() != 1)
        continue;
      auto call = dyn_cast<idr::CallOp>(uses.front());
      auto caller = call ? call->getParentOfType<idr::FuncOp>() : idr::FuncOp();
      if (!caller || caller == fn || component.lookup(caller) != component.lookup(fn) ||
          !fitsRegion(interface, call, fn))
        continue;
      if (failed(inlineCall(interface, config.getCloneCallback(), call, fn, &fn.getBody(),
                            /*shouldCloneInlinedRegion=*/false)))
        continue;
      caller.absorb(fn);
      call.erase();
      symbols.erase(fn);
      ++contified;
      changed = true;
    }
  }
  return contified;
}

struct Contify : idr::impl::IdrContifyBase<Contify> {
  void runOnOperation() override {
    unsigned contified = contify(getOperation(), getAnalysis<SymbolTable>());
    numContified += contified;
    if (!contified)
      return markAllAnalysesPreserved();
    // No type changed, and every function erased went through the table.
    markAnalysesPreserved<SymbolTable, idr::Holds, idr::TypeGraph, idr::Layouts>();
  }
};

} // namespace
