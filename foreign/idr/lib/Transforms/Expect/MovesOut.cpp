// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// moves-out: a read of an array's element whose next IO writes that
// element moves it out, stated as the property a test wants of it: some
// read gives the reference the array held, so the value it rebuilds holds
// the one reference to its cell.

#include "idr/Transforms/Expect.h"

#include "idr/IR/IdrDialect.h"

using namespace mlir;

namespace idr::expect {

// In the function the argument names and its clones, or anywhere, some
// idr.array.get moves its element out.
LogicalResult movesOut(ModuleOp module, AnalysisManager &, StringRef function) {
  constexpr StringRef property = "moves-out";
  SmallVector<Operation *> roots =
      rootsOf(module, function, property);
  if (roots.empty())
    return failure();
  bool moved = false;
  for (Operation *root : roots)
    root->walk([&](ArrayGetOp get) { moved = moved || get.getMoves(); });
  if (!moved)
    fail(roots.front()->getLoc(), property) << "no read of an element moves it out of its array"
                                            << (function.empty() ? "" : " in ") << function;
  return success(moved);
}

} // namespace idr::expect
