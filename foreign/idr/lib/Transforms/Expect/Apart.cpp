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

// `@f:@g`: some function is made from @f and some from @g, and none from
// both.
LogicalResult apart(ModuleOp module, AnalysisManager &, StringRef argument) {
  constexpr StringRef property = "apart";
  auto [first, second] = splitAt(module, argument, property);
  if (first.empty())
    return failure();
  SmallVector<FunctionOpInterface> fs = named(module, first, property);
  SmallVector<FunctionOpInterface> gs = named(module, second, property);
  if (fs.empty() || gs.empty())
    return failure();
  llvm::DenseSet<Operation *> fromFirst;
  for (FunctionOpInterface fn : fs)
    fromFirst.insert(fn);
  bool held = true;
  for (FunctionOpInterface fn : gs)
    if (fromFirst.contains(fn)) {
      fail(fn->getLoc(), property) << where(fn) << " is made from both " << first << " and "
                                   << second;
      held = false;
    }
  return success(held);
}

} // namespace idr::expect
