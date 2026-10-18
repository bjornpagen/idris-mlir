// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// An op made again with new operands and result types, its regions moved
// into it: what a conversion pattern does to an op whose types change and
// whose meaning does not. It is upstream's clone with the regions and
// operands left out, so the op's properties, discardable attributes and
// successors come with it as the clone has them, and nothing of the op is
// written out by hand. The caller replaces `op` by it. The operands keep the
// op's segment sizes, which come with the properties: a caller changes how
// many values an op takes only of an op with no segments.
#ifndef IDR_SUPPORT_REMAKE_H
#define IDR_SUPPORT_REMAKE_H

#include "mlir/IR/Builders.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/PatternMatch.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

namespace idr {

// `op` made again right before itself, taking `operands` and giving
// `results`, every region of `op` moved into the op made, in order.
inline mlir::Operation *remakeOp(mlir::RewriterBase &rewriter, mlir::Operation *op,
                                 mlir::ValueRange operands, mlir::TypeRange results) {
  mlir::IRMapping mapping;
  mlir::Operation *made =
      op->clone(mapping, mlir::Operation::CloneOptions::all()
                             .cloneRegions(false)
                             .cloneOperands(false)
                             .withResultTypes(llvm::to_vector(results)));
  made->setOperands(operands);
  mlir::OpBuilder::InsertionGuard guard(rewriter);
  rewriter.setInsertionPoint(op);
  rewriter.insert(made);
  for (auto [from, into] : llvm::zip_equal(op->getRegions(), made->getRegions()))
    rewriter.inlineRegionBefore(from, into, into.end());
  return made;
}

} // namespace idr

#endif // IDR_SUPPORT_REMAKE_H
