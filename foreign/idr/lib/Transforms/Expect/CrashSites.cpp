// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// How many places of a function may crash, counted the same before
// lowering and after it, for the contract crash-sites-not-added of every
// function a pass kept. Before it, a place is an op whose own effects end
// the run by a crash (idr.crash, a guard, which crashes when its condition
// fails, an exit whose status may be unreportable), as the effect system's
// one query reads its declaration; after it, each is a call of a function
// that never returns. So a guard
// lowered to one test and a crash, and the op it guards to no test of its
// own, keeps the count, and a guard that folded, or a primitive that tests
// again what its guard tested, changes it.

#include "idr/Transforms/Expect.h"

#include "idr/IR/Effects/Query.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"

using namespace mlir;

namespace idr::expect {

namespace {

// Whether `op` is a place that may crash: an op whose own effects write
// the crash state, or a call of the LLVM dialect that never returns (the
// call says so, or its callee). A call of the idr dialect is no place of
// its own: its callee's crashes are counted where they are.
bool crashes(Operation *op, SymbolTable &symbols) {
  auto call = dyn_cast<LLVM::CallOp>(op);
  if (!call && !isa<CallOpInterface>(op))
    return effects::own(op).on(effects::Kind::Write, effects::ResourceId::Crash);
  if (!call)
    return false;
  if (call.getNoreturn())
    return true;
  std::optional<StringRef> callee = call.getCallee();
  auto fn = callee ? symbols.lookup<LLVM::LLVMFuncOp>(*callee) : LLVM::LLVMFuncOp();
  return fn && fn.getNoreturn();
}

} // namespace

unsigned crashSitesOf(FunctionOpInterface fn, SymbolTable &symbols) {
  unsigned found = 0;
  fn->walk([&](Operation *op) { found += crashes(op, symbols); });
  return found;
}

} // namespace idr::expect
