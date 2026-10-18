// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// moves-out: an element of an array read only to be rebuilt and written
// back is rebuilt in its place, stated as the property a test wants of it:
// the element moves out of the array into the rebuilding, with the
// reference the array held, so the value it rebuilds holds the one
// reference to its cell. Every op that makes that move says so by its
// interface (UpdateOpInterface): idr.array.update on an array a world
// orders, and idr.element.update on the buffer of a value array.

#include "idr/Transforms/Expect.h"

#include "idr/IR/IdrDialect.h"

using namespace mlir;

namespace idr::expect {

// In the function the argument names and its clones, or anywhere, some
// element is rebuilt in its place.
LogicalResult movesOut(const Request<Roots> &request) {
  SmallVector<Operation *> roots = request.argument.roots(request.module);
  bool moved = false;
  for (Operation *root : roots)
    root->walk([&](UpdateOpInterface) { moved = true; });
  if (!moved)
    fail(roots.front()->getLoc(), request.property)
        << "no element of an array is rebuilt in its place" << request.argument.in();
  return success(moved);
}

} // namespace idr::expect
