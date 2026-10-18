// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// output-fused: no string is built only to be written. Output of a string
// its builder writes in pieces (StrBuilderOpInterface: a concatenation, a
// character before a string, one character, a number shown, a list packed
// or concatenated only to be written) writes the pieces instead; so
// idr.io.put_str never writes what such a builder made for it.

#include "idr/Transforms/Expect.h"

#include "idr/IR/IdrDialect.h"

using namespace mlir;

namespace idr::expect {

// No string is built only to be written, anywhere or in the function the
// argument names: idr.io.put_str never writes what a builder that writes in
// pieces made.
LogicalResult outputFused(const Request<Roots> &request) {
  bool held = true;
  for (Operation *root : request.argument.roots(request.module))
    root->walk([&](PutStrOp put) {
      auto builder = put.getStr().getDefiningOp<StrBuilderOpInterface>();
      if (!builder || !builder.writesInPieces())
        return;
      fail(put.getLoc(), request.property) << "idr.io.put_str writes what "
                                           << builder->getName() << " built in " << where(put);
      held = false;
    });
  return success(held);
}

} // namespace idr::expect
