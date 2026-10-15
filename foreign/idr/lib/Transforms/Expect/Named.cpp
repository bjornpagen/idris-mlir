// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The functions a property names. A test names the function the
// programmer wrote, by its symbol or by its Idris definition, and a
// property stated of it holds of every copy the passes made of it: a
// specialization, a copy made for a pass's own purpose, the one function
// deduplication kept of several. What a function is made from is in its
// location, which every pass keeps with what it copies: Emit names each
// function's location after its Idris definition, a copy is a clone of its
// original with the original's location, and deduplication fuses the
// locations of the functions it merges into the one it keeps. No fact a
// pass decides, and no name a pass makes, is read.

#include "idr/Transforms/Expect.h"

#include "mlir/IR/Location.h"
#include "llvm/ADT/SmallVector.h"

using namespace mlir;

namespace idr::expect {

// A location names `f` where a NameLoc called `f` is reached through the
// names and the fusions that wrap it: Emit's library wrapper is a fusion,
// and so is what deduplication made. A call site is no part of a
// function's own location.
bool names(FunctionOpInterface fn, StringRef f) {
  if (SymbolTable::getSymbolName(fn).getValue() == f)
    return true;
  SmallVector<Location> pending{fn->getLoc()};
  while (!pending.empty()) {
    Location loc = pending.pop_back_val();
    if (auto named = dyn_cast<NameLoc>(loc)) {
      if (named.getName().getValue() == f)
        return true;
      pending.push_back(named.getChildLoc());
    } else if (auto fused = dyn_cast<FusedLoc>(loc)) {
      llvm::append_range(pending, fused.getLocations());
    }
  }
  return false;
}

SmallVector<FunctionOpInterface> named(ModuleOp module, StringRef function, StringRef property) {
  SmallVector<FunctionOpInterface> functions;
  StringRef f = function.ltrim('@');
  if (f.empty()) {
    fail(module.getLoc(), property) << "no function named";
    return functions;
  }
  for (auto fn : module.getOps<FunctionOpInterface>())
    if (names(fn, f))
      functions.push_back(fn);
  if (functions.empty())
    fail(module.getLoc(), property) << "no function " << function << ", and no copy of it";
  return functions;
}

SmallVector<Operation *> rootsOf(ModuleOp module, StringRef function, StringRef property) {
  SmallVector<Operation *> roots;
  if (function.empty()) {
    roots.push_back(module);
    return roots;
  }
  for (FunctionOpInterface fn : named(module, function, property))
    roots.push_back(fn);
  return roots;
}

} // namespace idr::expect
