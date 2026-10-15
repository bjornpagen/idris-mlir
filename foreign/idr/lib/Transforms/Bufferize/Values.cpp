// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Two ops that hold a tensor without touching its elements: idr.tie_shape,
// which names an array's dynamic sizes, and ub.poison, which dead-value
// removal leaves where a kept op used a dead array.
#include "idr/Transforms/BufferizeModels.h"

#include "mlir/Dialect/Bufferization/IR/Bufferization.h"
#include "mlir/Dialect/UB/IR/UBOps.h"

using namespace mlir;
using namespace mlir::bufferization;

namespace {

// The same array, its sizes named: the buffer is the operand's, and the
// op stays on it, so value bounds still relate the sizes of buffers across
// a call until idr-lower drops it.
struct TieShapeModel : BufferizableOpInterface::ExternalModel<TieShapeModel, idr::TieShapeOp> {
  bool bufferizesToMemoryRead(Operation *, OpOperand &, const AnalysisState &) const {
    return false;
  }
  bool bufferizesToMemoryWrite(Operation *, OpOperand &, const AnalysisState &) const {
    return false;
  }
  AliasingValueList getAliasingValues(Operation *op, OpOperand &, const AnalysisState &) const {
    return {{op->getResult(0), BufferRelation::Equivalent, /*isDefinite=*/true}};
  }

  FailureOr<BufferLikeType> getBufferType(Operation *op, Value, const BufferizationOptions &options,
                                          const BufferizationState &state,
                                          SmallVector<Value> &invocationStack) const {
    return bufferization::getBufferType(op->getOperand(0), options, state, invocationStack);
  }

  LogicalResult bufferize(Operation *op, RewriterBase &rewriter,
                          const BufferizationOptions &options, BufferizationState &state) const {
    FailureOr<Value> buffer = getBuffer(rewriter, op->getOperand(0), options, state);
    if (failed(buffer))
      return failure();
    Operation *tied = rewriter.clone(*op);
    tied->setOperand(0, *buffer);
    tied->getResult(0).setType(buffer->getType());
    replaceOpWithBufferizedValues(rewriter, op, tied->getResults());
    return success();
  }
};

// Upstream gives ub.poison no model. A poison array is a dead value a kept
// op still names, so its buffer is never read or written: a poison buffer,
// no allocation and no copy. Its contents are undefined, so it defines
// nothing a read could see.
struct PoisonModel : BufferizableOpInterface::ExternalModel<PoisonModel, ub::PoisonOp> {
  AliasingOpOperandList getAliasingOpOperands(Operation *, Value, const AnalysisState &) const {
    return {};
  }
  bool resultBufferizesToMemoryWrite(Operation *, OpResult, const AnalysisState &) const {
    return false;
  }
  bool isWritable(Operation *, Value, const AnalysisState &) const { return true; }
  bool bufferizesToAllocation(Operation *, Value) const { return false; }

  FailureOr<BufferLikeType> getBufferType(Operation *, Value value, const BufferizationOptions &,
                                          const BufferizationState &,
                                          SmallVector<Value> &) const {
    return idr::bufferize::cellType(value);
  }

  LogicalResult bufferize(Operation *op, RewriterBase &rewriter, const BufferizationOptions &,
                          BufferizationState &) const {
    replaceOpWithNewBufferizedOp<ub::PoisonOp>(
        rewriter, op,
        idr::bufferize::bufferType(cast<RankedTensorType>(op->getResult(0).getType())));
    return success();
  }
};

} // namespace

void idr::bufferize::attachTieShapeModel(MLIRContext *ctx) {
  idr::TieShapeOp::attachInterface<TieShapeModel>(*ctx);
}

void idr::bufferize::attachPoisonModel(MLIRContext *ctx) {
  ub::PoisonOp::attachInterface<PoisonModel>(*ctx);
}
