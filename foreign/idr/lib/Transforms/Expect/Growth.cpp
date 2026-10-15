// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// grows-nothing: a pass that moves code into the regions of a match copies
// it into each, so where nothing there folds the function only grows. That
// it did not is stated against the module the passes started from, read
// from its file: the function is no larger than it was.

#include "idr/Transforms/Expect.h"

#include "mlir/Parser/Parser.h"

using namespace mlir;

namespace idr::expect {

namespace {

// How many operations the body of `fn` holds, nested ones included.
int64_t sizeOf(FunctionOpInterface fn) {
  int64_t size = 0;
  fn.getFunctionBody().walk([&](Operation *) { ++size; });
  return size;
}

} // namespace

// `@f:<file>`: every copy of @f holds at most as many operations as the
// function of that symbol in the module <file> holds.
LogicalResult growsNothing(ModuleOp module, AnalysisManager &, StringRef argument) {
  constexpr StringRef property = "grows-nothing";
  auto [function, file] = argument.split(':');
  if (function.ltrim('@').empty() || file.empty())
    return fail(module.getLoc(), property) << "name the function and the module it started in, as "
                                              "grows-nothing=@f:<file>";
  OwningOpRef<ModuleOp> before = parseSourceFile<ModuleOp>(file, module.getContext());
  if (!before)
    return fail(module.getLoc(), property) << "cannot read " << file;
  StringRef f = function.ltrim('@');
  FunctionOpInterface was;
  for (FunctionOpInterface fn : functionsOf(*before))
    if (SymbolTable::getSymbolName(fn).getValue() == f)
      was = fn;
  if (!was)
    return fail(module.getLoc(), property) << file << " has no function " << function;
  SmallVector<FunctionOpInterface> functions = named(module, function, property);
  if (functions.empty())
    return failure();
  bool held = true;
  for (FunctionOpInterface fn : functions)
    if (sizeOf(fn) > sizeOf(was)) {
      fail(fn->getLoc(), property) << where(fn) << " holds " << sizeOf(fn) << " operations, and "
                                   << sizeOf(was) << " before";
      held = false;
    }
  return success(held);
}

} // namespace idr::expect
