// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// crash-sites: how many places of a function may crash, stated the same
// before lowering and after it, and counted for the contracts of every
// function a pass kept. Before it, a place is an op that never returns
// (idr.crash, an exit) or a guard, which crashes when its condition fails;
// after it, each is a call of a function that never returns. So a guard
// lowered to one test and a crash, and the op it guards to no test of its
// own, keeps the count, and a guard that folded, or a primitive that tests
// again what its guard tested, changes it.

#include "idr/Transforms/Expect.h"

#include "idr/IR/IdrDialect.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"

using namespace mlir;

namespace idr::expect {

namespace {

// Whether `op` is a place that may crash: an idr op that never returns, a
// guard, or a call of the LLVM dialect that never returns (the call says
// so, or its callee).
bool crashes(Operation *op, SymbolTable &symbols) {
  if (op->hasTrait<NoReturn>() || isa<GuardOpInterface>(op))
    return true;
  auto call = dyn_cast<LLVM::CallOp>(op);
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

// Every copy of @f may crash at exactly the number of places the argument
// gives.
LogicalResult crashSites(const Request<CountOf> &request) {
  unsigned wanted = request.argument.count;
  SymbolTable &symbols = symbolsOf(request.module, request.analyses);
  bool held = true;
  for (FunctionOpInterface fn : request.argument.function.functions) {
    unsigned found = crashSitesOf(fn, symbols);
    if (found == wanted)
      continue;
    fail(fn->getLoc(), request.property) << where(fn) << " may crash at " << found
                                         << " places, not " << wanted;
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
