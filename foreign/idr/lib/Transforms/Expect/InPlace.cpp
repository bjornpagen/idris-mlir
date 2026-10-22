// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// in-place: what bufferization guarantees of a linear thread, stated as
// the absence of a copy. A copy bufferization makes is its own op, a copy
// into a buffer allocated for it (idr.array.place_copy), never the write of
// a slice into a live buffer, which is the meaning of the op it came from.

#include "idr/Transforms/Expect.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/BuiltinTypes.h"

using namespace mlir;

namespace idr::expect {

// In the function the argument names or anywhere, nothing copies a buffer,
// and a buffer is there, so the property cannot hold of a module before
// bufferization or without an array.
LogicalResult inPlace(const Request<Roots> &request) {
  SmallVector<Operation *> roots = request.argument.roots(request.module);
  bool held = true, buffer = false;
  // A linear buffer is a buffer in its grade's wrapper.
  auto isBuffer = [](Type type) { return isa<MemRefType>(unrestricted(type)); };
  for (Operation *root : roots)
    root->walk([&](Operation *op) {
      buffer = buffer || llvm::any_of(op->getResultTypes(), isBuffer) ||
               llvm::any_of(op->getOperandTypes(), isBuffer);
      if (!isa<ArrayPlaceCopyOp>(op))
        return;
      fail(op->getLoc(), request.property) << op->getName() << " copies a buffer in " << where(op);
      held = false;
    });
  if (!buffer) {
    fail(roots.front()->getLoc(), request.property) << "no buffer" << request.argument.in();
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
