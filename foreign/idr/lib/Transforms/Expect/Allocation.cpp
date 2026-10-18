// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// no-heap-allocation: nothing allocates a heap cell, in one function and
// what it may call, or in the whole module. This is how a test states that
// a value stays off the heap, whatever ops show it.

#include "idr/Transforms/Expect.h"

#include "idr/IR/IdrDialect.h"
#include "idr/Support/Worklist.h"

#include "mlir/IR/Matchers.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"

#include <optional>

using namespace mlir;

namespace idr::expect {

namespace {

// What `op` allocates, or nothing. An op says so by an Allocate effect; a
// closure is the one exception, Pure as a value but built in a cell at
// runtime.
std::optional<std::string> allocation(Operation *op) {
  if (auto closure = dyn_cast<ClosureOp>(op))
    return "a closure of @" + closure.getCallee().str() + " is built";
  if (auto suspend = dyn_cast<SuspendOp>(op))
    return "a suspension of @" + suspend.getCallee().str() + " is built";
  // idr.lin.enter and idr.lin.use allocate a new value, not memory; a cell
  // in its function's frame (idr.cell.stack) is stack memory.
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
// function its body names, by a call or a closure, each taken once.
LogicalResult noHeapAllocation(const Request<Roots> &request) {
  ModuleOp module = request.module;
  const std::optional<Functions> &scope = request.argument.scope;
  OnceWorklist<Operation *> reached;
  for (FunctionOpInterface fn : scope ? scope->functions : functionsOf(module))
    reached.push(fn);
  SymbolTable *symbols = scope ? &symbolsOf(module, request.analyses) : nullptr;
  bool held = true;
  while (std::optional<Operation *> next = reached.pop()) {
    auto fn = cast<FunctionOpInterface>(*next);
    if (fn.isExternal()) {
      if (symbols) {
        fail(fn->getLoc(), request.property)
            << where(fn) << " may be called, and its body is not in the module";
        held = false;
      }
      continue;
    }
    fn->walk([&](Operation *op) {
      if (std::optional<std::string> found = allocation(op)) {
        fail(op->getLoc(), request.property) << *found << " in " << where(op);
        held = false;
      }
      auto apply = dyn_cast<ApplyOp>(op);
      if (symbols && apply && !matchPattern(apply.getCallee(), m_Constant())) {
        fail(op->getLoc(), request.property) << where(op) << " applies a closure made outside it";
        held = false;
      }
    });
    // After lowering a body calls the runtime, whose functions are
    // declarations: the property is one of the idr functions.
    if (!symbols || !isa<FuncOp>(fn.getOperation()))
      continue;
    for (Operation *callee : callees(*symbols, fn))
      reached.push(callee);
  }
  return success(held);
}

} // namespace idr::expect
