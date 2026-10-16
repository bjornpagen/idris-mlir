// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-contify: an idr.func other than the program's root whose one use is a
// call from another function on a cycle of calls with it becomes part of
// that function: its body moves into the call, with MLIR's inlineCall, and
// the function goes.
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
// it too (FuncOp::absorb). One sweep over the functions, in program order,
// moves every function that qualifies, the components and the users taken
// once before it. A move erases a function whose one edge in comes from its
// caller in its own component, so every path through it now runs through
// the caller: no other function changes component, and no other function
// gains or loses a use, since a moved call keeps its op. A function's body
// only grows blocks and a call stays in the region that holds it, so a
// function that does not fit its call site when the sweep reaches it never
// fits later. Nothing qualifies after the sweep that did not before it.

#include "idr/Transforms/Optimize.h"

#include "idr/Analysis/Effects.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/TypeGraph.h"
#include "idr/Support/Actions.h"
#include "idr/Transforms/Inline.h"

#include "mlir/Analysis/CallGraph.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Transforms/Inliner.h"
#include "mlir/Transforms/InliningUtils.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

namespace idr {
#define GEN_PASS_DEF_IDRCONTIFY
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace {

// One move of a function into its one call, which then goes with the
// function; its IR unit is the call.
struct ContifyMoveAction : idr::support::TaggedAction<ContifyMoveAction> {
  using TaggedAction::TaggedAction;
  static constexpr llvm::StringLiteral tag = "idr-contify-move";
};

// The component of the call graph each function is in, by its number.
llvm::DenseMap<Operation *, unsigned> componentsOf(const CallGraph &graph) {
  llvm::DenseMap<Operation *, unsigned> component;
  for (auto [number, members] : llvm::enumerate(idr::callGraphComponents(graph)))
    for (idr::FuncOp fn : members)
      component.try_emplace(fn, static_cast<unsigned>(number));
  return component;
}

// Moves every function of one call from another member of its component
// into that call; how many. The root is also called from outside the
// program, so it never moves.
unsigned contify(idr::ProgramOp program, SymbolTable &symbols, const CallGraph &graph) {
  unsigned contified = 0;
  InlinerInterface interface(program.getContext());
  InlinerConfig config;
  SmallVector<idr::FuncOp> fns(program.getOps<idr::FuncOp>());
  llvm::DenseMap<Operation *, unsigned> component = componentsOf(graph);
  // The users of every function as the sweep begins. A body moved into its
  // caller keeps its uses, now in the caller; the one call moved goes with
  // the function it named.
  SymbolTableCollection tables;
  SymbolUserMap users(tables, program);
  for (idr::FuncOp fn : fns) {
    ArrayRef<Operation *> uses = users.getUsers(fn);
    if (uses.size() != 1 || fn.getSymName() == program.getRoot())
      continue;
    auto call = dyn_cast<idr::CallOp>(uses.front());
    auto caller = call ? call->getParentOfType<idr::FuncOp>() : idr::FuncOp();
    if (!caller || caller == fn || component.at(caller) != component.at(fn) ||
        !idr::inlining::fitsRegion(interface, call, fn))
      continue;
    // A skipped move leaves the function and its one call, and the users
    // the sweep took before it began stay true.
    bool moved = false;
    (void)idr::support::perform<ContifyMoveAction>(call, [&] {
      if (failed(inlineCall(interface, config.getCloneCallback(), call, fn, &fn.getBody(),
                            /*shouldCloneInlinedRegion=*/false)))
        return;
      caller.absorb(fn);
      call.erase();
      symbols.erase(fn);
      moved = true;
    });
    if (moved)
      ++contified;
  }
  return contified;
}

struct Contify : idr::impl::IdrContifyBase<Contify> {
  void runOnOperation() override {
    unsigned contified =
        contify(getOperation(), getAnalysis<SymbolTable>(), getAnalysis<CallGraph>());
    numContified += contified;
    if (!contified)
      return markAllAnalysesPreserved();
    // No type changed, and every function erased went through the table.
    markAnalysesPreserved<SymbolTable, idr::TypeGraph, idr::Layouts>();
  }
};

} // namespace
