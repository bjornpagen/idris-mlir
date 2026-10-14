// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// no-heap-allocation: nothing allocates a heap cell, in one function and
// what it may call, or in the whole module. This is how a test states that
// a value stays off the heap, whatever ops show it.

#include "idr/Transforms/Expect.h"

#include "idr/Analysis/References.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Matchers.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "llvm/ADT/DenseSet.h"

#include <optional>

using namespace mlir;

namespace idr::expect {

namespace {

constexpr StringRef property = "no-heap-allocation";

// What `op` allocates, or nothing. An op says so by an Allocate effect; a
// closure is the one exception, Pure as a value but built in a cell at
// runtime.
std::optional<std::string> allocation(Operation *op) {
  if (auto closure = dyn_cast<ClosureOp>(op))
    return "a closure of @" + closure.getCallee().str() + " is built";
  if (auto suspend = dyn_cast<SuspendOp>(op))
    return "a suspension of @" + suspend.getCallee().str() + " is built";
  // idr.lin.enter and idr.lin.use allocate a new value, not memory; a cell
  // idr-stack keeps in its frame is stack memory.
  if (auto effects = dyn_cast<MemoryEffectOpInterface>(op)) {
    SmallVector<MemoryEffects::EffectInstance> all;
    effects.getEffects(all);
    if (llvm::any_of(all, [](const MemoryEffects::EffectInstance &effect) {
          return isa<MemoryEffects::Allocate>(effect.getEffect()) &&
                 !isa<LinResource, SideEffects::AutomaticAllocationScopeResource>(
                     effect.getResource());
        }))
      return (op->getName().getStringRef() + " allocates").str();
  }
  return std::nullopt;
}

} // namespace

// In one function's scope, what it may call is in scope too: every
// function its body names, by a call or a closure, as References found
// them.
LogicalResult noHeapAllocation(ModuleOp module, AnalysisManager &analyses, StringRef function) {
  SmallVector<FunctionOpInterface> reached;
  llvm::DenseSet<Operation *> seen;
  References *references = nullptr;
  if (function.empty()) {
    for (auto fn : module.getOps<FunctionOpInterface>())
      reached.push_back(fn);
  } else {
    reached = named(module, analyses.getAnalysis<SymbolTable>(), function, property);
    if (reached.empty())
      return failure();
    seen.insert(reached.begin(), reached.end());
    references = &analyses.getAnalysis<References>();
  }
  bool held = true;
  for (size_t next = 0; next < reached.size(); ++next) {
    FunctionOpInterface fn = reached[next];
    if (fn.isExternal()) {
      if (references) {
        fail(fn->getLoc(), property) << where(fn) << " may be called, and its body is not in the module";
        held = false;
      }
      continue;
    }
    fn->walk([&](Operation *op) {
      if (std::optional<std::string> found = allocation(op)) {
        fail(op->getLoc(), property) << *found << " in " << where(op);
        held = false;
      }
      auto apply = dyn_cast<ApplyOp>(op);
      if (references && apply && !matchPattern(apply.getCallee(), m_Constant())) {
        fail(op->getLoc(), property) << where(op) << " applies a closure made outside it";
        held = false;
      }
    });
    if (!references || !isa<FuncOp>(fn.getOperation()))
      continue;
    for (Operation *callee : referencedBy(*references, fn))
      if (seen.insert(callee).second)
        reached.push_back(cast<FunctionOpInterface>(callee));
  }
  return success(held);
}

} // namespace idr::expect
