// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The one partition of a module's functions into their cycles of calls,
// cached by the analysis manager: upstream's call graph (mlir::CallGraph,
// itself a cached analysis) walked as upstream's inliner walks it, with
// LLVM's scc_iterator from the graph's external node. That node's abstract
// edges reach every callable, so one walk meets them all, callees first, in
// an order the module alone fixes. Every pass that asks which functions
// share a cycle of calls, or goes through them callees first, reads this.
//
// A function is the operation that holds it: an idr.func, or after lowering
// a func.func or an llvm.func. One the module declares with no body (a
// runtime function of a lowered module) has no callable region, so the
// graph has no node for it, and a call of it reaches the graph's unknown
// callee. Here it is a component of its own, on no cycle, ahead of every
// component that holds a body, since it calls nothing. So every function
// the module declares has a component, and componentOf and together answer
// for any two of them.
#ifndef IDR_ANALYSIS_CALLCYCLES_H
#define IDR_ANALYSIS_CALLCYCLES_H

#include "mlir/IR/Operation.h"
#include "mlir/Pass/AnalysisManager.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/SmallVector.h"

namespace idr {

class CallCycles {
public:
  // The functions of one component, in scc_iterator's order.
  using Component = llvm::SmallVector<mlir::Operation *, 1>;

  CallCycles(mlir::Operation *op, mlir::AnalysisManager &am);
  bool isInvalidated(const mlir::AnalysisManager::PreservedAnalyses &pa) const;

  // Every component, callees first: a component's callees outside it are
  // members of earlier ones, every function with no body among them.
  llvm::ArrayRef<Component> components() const { return all; }
  // The index in components() of the component of `fn`, a function the
  // module declares.
  unsigned componentOf(mlir::Operation *fn) const;
  // Whether `a` and `b` are on one cycle of calls: each may call the
  // other, through any calls. A function is on one with itself, and a
  // function with no body with nothing else.
  bool together(mlir::Operation *a, mlir::Operation *b) const;
  // Whether `fn`, alone in its component, calls itself; never one with no
  // body. A member of a component of two or more is on the cycle
  // components() shows.
  bool callsItself(mlir::Operation *fn) const;

private:
  llvm::SmallVector<Component> all;
  llvm::DenseMap<mlir::Operation *, unsigned> indices;
  // The functions alone in their component whose component has a cycle.
  llvm::DenseSet<mlir::Operation *> selfCalling;
};

} // namespace idr

#endif // IDR_ANALYSIS_CALLCYCLES_H
