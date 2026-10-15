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

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Location.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

using namespace mlir;

namespace idr::expect {

Operation *programOf(ModuleOp module) {
  for (ProgramOp program : module.getOps<ProgramOp>())
    return program;
  return module;
}

SmallVector<FunctionOpInterface> functionsOf(ModuleOp module) {
  return llvm::to_vector(programOf(module)->getRegion(0).getOps<FunctionOpInterface>());
}

// The table is the analysis of the program's own op, so it lives as long as
// the pass's analyses and is built by whichever property asks first.
SymbolTable &symbolsOf(ModuleOp module, AnalysisManager &analyses) {
  Operation *program = programOf(module);
  if (program == module.getOperation())
    return analyses.getAnalysis<SymbolTable>();
  return analyses.nest(program).getAnalysis<SymbolTable>();
}

namespace {

// A location names `f` where a NameLoc called `f` is reached through the
// names and the fusions that wrap it: Emit's library wrapper is a fusion,
// and so is what deduplication made. A call site is no part of a
// function's own location. Each step is into a part of the location, which
// is built before it, so the descent ends.
bool locationNames(Location loc, StringRef f) {
  if (auto named = dyn_cast<NameLoc>(loc))
    return named.getName().getValue() == f || locationNames(named.getChildLoc(), f);
  if (auto fused = dyn_cast<FusedLoc>(loc))
    return llvm::any_of(fused.getLocations(),
                        [&](Location part) { return locationNames(part, f); });
  return false;
}

} // namespace

bool names(FunctionOpInterface fn, StringRef f) {
  return SymbolTable::getSymbolName(fn).getValue() == f || locationNames(fn->getLoc(), f);
}

SmallVector<FunctionOpInterface> named(ModuleOp module, StringRef function, StringRef property) {
  SmallVector<FunctionOpInterface> functions;
  StringRef f = function.ltrim('@');
  if (f.empty()) {
    fail(module.getLoc(), property) << "no function named";
    return functions;
  }
  for (FunctionOpInterface fn : functionsOf(module))
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
