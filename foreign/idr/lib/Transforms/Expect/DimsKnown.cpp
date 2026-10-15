// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// dims-known: a function asks the extent of no array it made: the extent
// it was made with is that value, so the fold of the question to it leaves
// no read of the array's size. Only an array the function was given has
// extents it must ask.

#include "idr/Transforms/Expect.h"

#include "mlir/Interfaces/ShapedOpInterfaces.h"

using namespace mlir;

namespace idr::expect {

// In every copy of @f, every dimension op (ShapedDimOpInterface: memref.dim,
// tensor.dim) asks it of a block argument, not of a value an op made.
LogicalResult dimsKnown(ModuleOp module, AnalysisManager &, StringRef function) {
  constexpr StringRef property = "dims-known";
  SmallVector<FunctionOpInterface> functions = named(module, function, property);
  if (functions.empty())
    return failure();
  bool held = true;
  for (FunctionOpInterface fn : functions)
    fn->walk([&](ShapedDimOpInterface dim) {
      Operation *made = dim.getShapedValue().getDefiningOp();
      if (!made)
        return;
      fail(dim->getLoc(), property) << dim->getName() << " in " << where(fn)
                                    << " asks an extent of what " << made->getName() << " made";
      held = false;
    });
  return success(held);
}

} // namespace idr::expect
