// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// grows-nothing: a pass that moves code into the regions of a match copies
// it into each, so where nothing there folds the function only grows. That
// it did not is stated against the module the passes started from, read
// from its file: the function is no larger than it was.

#include "idr/Transforms/Expect.h"

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

// Every copy of @f holds at most as many operations as the function of
// that symbol in the module the file holds, which must have one.
LogicalResult growsNothing(const Request<FunctionsAndModule> &request) {
  StringRef f = request.argument.function.name;
  ModuleOp before = *request.argument.module.op;
  FunctionOpInterface was;
  for (FunctionOpInterface fn : functionsOf(before))
    if (SymbolTable::getSymbolName(fn).getValue() == f)
      was = fn;
  if (!was)
    return fail(request.module->getLoc(), request.property)
           << "the module it started in has no function @" << f;
  bool held = true;
  for (FunctionOpInterface fn : request.argument.function.functions)
    if (sizeOf(fn) > sizeOf(was)) {
      fail(fn->getLoc(), request.property) << where(fn) << " holds " << sizeOf(fn)
                                           << " operations, and " << sizeOf(was) << " before";
      held = false;
    }
  return success(held);
}

} // namespace idr::expect
