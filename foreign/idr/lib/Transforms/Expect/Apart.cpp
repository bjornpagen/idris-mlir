// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// apart: two functions the programmer wrote are still two: no function of
// the program is made from both. Deduplication fuses the locations of the
// functions it merges into the one it keeps, so a function made from both
// is one whose location names both (`names`); that none is, and that each
// is still there, is the property.

#include "idr/Transforms/Expect.h"

#include "llvm/ADT/DenseSet.h"

using namespace mlir;

namespace idr::expect {

// Some function is made from @f and some from @g, which the argument's
// parser found, and none from both.
LogicalResult apart(const Request<TwoFunctions> &request) {
  const TwoFunctions &pair = request.argument;
  llvm::DenseSet<Operation *> fromFirst;
  for (FunctionOpInterface fn : pair.first.functions)
    fromFirst.insert(fn);
  bool held = true;
  for (FunctionOpInterface fn : pair.second.functions)
    if (fromFirst.contains(fn)) {
      fail(fn->getLoc(), request.property) << where(fn) << " is made from both @"
                                           << pair.first.name << " and @" << pair.second.name;
      held = false;
    }
  return success(held);
}

} // namespace idr::expect
