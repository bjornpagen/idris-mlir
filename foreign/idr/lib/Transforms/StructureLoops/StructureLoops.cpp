// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-structure-loops: each op of the generating set lowered once, in one
// walk. The walk visits an op after the ops inside its region, so an op is
// decided with what its region holds already lowered, and what a lowering
// makes holds no op of the generating set: nothing is visited twice, and
// nothing is left that the pass would still take.

#include "idr/Transforms/StructureLoops.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Linalg/IR/Linalg.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/Tensor/IR/Tensor.h"
#include "mlir/Dialect/UB/IR/UBOps.h"

namespace idr {
#define GEN_PASS_DEF_IDRSTRUCTURELOOPS
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::structure {

void lower(RewriterBase &rewriter, Operation *op, Form form) {
  switch (form) {
  case Form::Parallel:
    return lowerParallel(rewriter, op);
  case Form::Reduction:
    return lowerReduction(rewriter, cast<FoldLastOp>(op));
  case Form::Interchange:
    return lowerInterchange(rewriter, op);
  case Form::Ordered:
    return lowerOrdered(rewriter, op);
  }
  llvm_unreachable("every form is lowered");
}

namespace {

struct StructureLoops : idr::impl::IdrStructureLoopsBase<StructureLoops> {
  void runOnOperation() override {
    SmallVector<Operation *> ops;
    getOperation()->walk<WalkOrder::PostOrder>([&](Operation *op) {
      if (structurable(op))
        ops.push_back(op);
    });
    SymbolTableCollection symbols;
    IRRewriter rewriter(&getContext());
    for (Operation *op : ops) {
      Form form = formOf(op, symbols);
      lower(rewriter, op, form);
      ++(form == Form::Reduction ? numReductions
         : form == Form::Ordered ? numOrdered
                                 : numParallel);
    }
  }
};

} // namespace

} // namespace idr::structure
