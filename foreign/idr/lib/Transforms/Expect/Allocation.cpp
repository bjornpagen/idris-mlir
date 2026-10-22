// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// no-heap-allocation: nothing allocates a heap cell, in one function and
// what it may call, or in the whole module. This is how a test states that
// a value stays off the heap, whatever ops show it.

#include "idr/Transforms/Expect.h"

#include "idr/IR/Effects/Whole.h"
#include "idr/IR/IdrDialect.h"


#include <optional>

using namespace mlir;

namespace idr::expect {

namespace {

// What `op` acquires of the heap, or nothing: an Allocate the op declares
// on the heap, the memory every cell lives in, read through the effect
// system's one query. Building a value acquires nothing until counting
// makes its cell (a constructor, a closure and a suspension are values
// until then), and a fresh identity or a frame's slot is no heap memory,
// so the declaration says it all.
std::optional<std::string> allocation(Operation *op) {
  if (effects::own(op).on(effects::Kind::Allocate, effects::ResourceId::Heap))
    return (op->getName().getStringRef() + " acquires heap memory").str();
  return std::nullopt;
}

} // namespace

// In one function's scope, what it may call is in scope too: every
// function its body names, by a call or a closure, each taken once.
LogicalResult noHeapAllocation(const Request<Roots> &request) {
  ModuleOp module = request.module;
  const std::optional<Functions> &scope = request.argument.scope;
  SymbolTable *symbols = scope ? &symbolsOf(module, request.analyses) : nullptr;
  SmallVector<Operation *> roots;
  for (FunctionOpInterface fn : scope ? scope->functions : functionsOf(module))
    roots.push_back(fn);
  // After lowering a body calls the runtime, whose functions are
  // declarations: the property is one of the idr functions.
  auto edges = [&](Operation *fn) {
    auto function = cast<FunctionOpInterface>(fn);
    if (!symbols || function.isExternal() || !isa<FuncOp>(fn))
      return SmallVector<Operation *>();
    return callees(*symbols, fn);
  };
  bool held = true;
  for (Operation *next : reachable(roots, edges)) {
    auto fn = cast<FunctionOpInterface>(next);
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
    });
  }
  return success(held);
}

} // namespace idr::expect
