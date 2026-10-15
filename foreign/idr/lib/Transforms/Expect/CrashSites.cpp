// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// crash-sites: how many places of a function may crash, stated the same
// before lowering and after it. Before it, a place is an op that never
// returns (idr.crash, an exit) or a guard, which crashes when its
// condition fails; after it, each is a call of a function that never
// returns. So a guard lowered to one test and a crash, and the op it
// guards to no test of its own, keeps the count, and a guard that folded,
// or a primitive that tests again what its guard tested, changes it.

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

// Every copy of @f may crash at exactly the number of places the argument
// gives.
LogicalResult crashSites(ModuleOp module, AnalysisManager &analyses, StringRef argument) {
  constexpr StringRef property = "crash-sites";
  auto [function, count] = splitAt(module, argument, property);
  if (function.empty())
    return failure();
  unsigned wanted = 0;
  if (count.getAsInteger(10, wanted))
    return fail(module.getLoc(), property) << "name the count, as crash-sites=@f:<n>";
  SmallVector<FunctionOpInterface> functions = named(module, function, property);
  if (functions.empty())
    return failure();
  SymbolTable &symbols = symbolsOf(module, analyses);
  bool held = true;
  for (FunctionOpInterface fn : functions) {
    unsigned found = 0;
    fn->walk([&](Operation *op) { found += crashes(op, symbols); });
    if (found == wanted)
      continue;
    fail(fn->getLoc(), property) << where(fn) << " may crash at " << found << " places, not "
                                 << wanted;
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
