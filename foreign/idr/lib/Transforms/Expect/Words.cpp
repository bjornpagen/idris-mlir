// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// word-loop: what idr-narrow guarantees of a loop whose naturals it proves
// small, stated as the absence of any big in the loop rather than as the ops
// that happen to replace them.

#include "idr/Transforms/Expect.h"

#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Narrow.h"

#include "mlir/Interfaces/LoopLikeInterface.h"

using namespace mlir;

namespace idr::expect {

// Some loop of the function (or of a clone of it) computes on words alone:
// no value defined or bound in it is a big or a natural, so no tag is
// tested in it and no runtime call on bigs is made from it.
LogicalResult wordLoop(const Request<Functions> &request) {
  ArrayRef<FunctionOpInterface> functions = request.argument.functions;
  unsigned loops = 0;
  bool found = false;
  for (FunctionOpInterface fn : functions)
    fn->walk([&](LoopLikeOpInterface loop) {
      ++loops;
      WalkResult big = loop->walk([&](Operation *op) {
        for (Region &region : op->getRegions())
          for (Block &block : region)
            if (llvm::any_of(block.getArgumentTypes(), narrow::isBig))
              return WalkResult::interrupt();
        if (llvm::any_of(op->getOperandTypes(), narrow::isBig) ||
            llvm::any_of(op->getResultTypes(), narrow::isBig))
          return WalkResult::interrupt();
        return WalkResult::advance();
      });
      found |= !big.wasInterrupted();
    });
  if (found)
    return success();
  fail(functions.front()->getLoc(), request.property)
      << "@" << request.argument.name
      << (loops == 0 ? " has no loop" : " computes on bigs in each of its loops");
  return failure();
}

} // namespace idr::expect
