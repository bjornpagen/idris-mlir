// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Three ops that hold a tensor without touching its elements:
// idr.array.tie_shape, which names an array's dynamic sizes; idr.carrier,
// which lends a value's bare carrier to upstream's ops under a lifetime;
// and ub.poison, which dead-value removal leaves where a kept op used a
// dead array.
#include "idr/Transforms/BufferizeModels.h"

#include "mlir/Dialect/Bufferization/IR/Bufferization.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/Interfaces/ViewLikeInterface.h"

using namespace mlir;
using namespace mlir::bufferization;

namespace {

// The same array, its sizes named: the buffer is the operand's, and the
// op stays on it, so value bounds still relate the sizes of buffers across
// a call until idr-lower drops it.
struct TieShapeModel : BufferizableOpInterface::ExternalModel<TieShapeModel, idr::ArrayTieShapeOp> {
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

// A loan: the value's own words, which its holder keeps, handed to
// upstream's ops as the bare carrier they take. Its buffer is the value's,
// at no grade, never a copy, since the loan is those words; and it writes
// nothing, as upstream's to_buffer of a read-only buffer hands a buffer on.
// The buffer stays its holder's, so nothing writes it through the loan: the
// result is not writable, and One-Shot copies for a write to it. The source
// is read through its view interface.
struct CarrierModel : BufferizableOpInterface::ExternalModel<CarrierModel, idr::CarrierOp> {
  static Value sourceOf(Operation *op) { return cast<ViewLikeOpInterface>(op).getViewSource(); }

  bool bufferizesToMemoryRead(Operation *, OpOperand &, const AnalysisState &) const {
    return true;
  }
  bool bufferizesToMemoryWrite(Operation *, OpOperand &, const AnalysisState &) const {
    return false;
  }
  bool mustBufferizeInPlace(Operation *, OpOperand &, const AnalysisState &) const {
    return true;
  }
  bool isWritable(Operation *, Value, const AnalysisState &) const { return false; }
  AliasingValueList getAliasingValues(Operation *op, OpOperand &, const AnalysisState &) const {
    return {{op->getResult(0), BufferRelation::Equivalent, /*isDefinite=*/true}};
  }

  FailureOr<BufferLikeType> getBufferType(Operation *op, Value, const BufferizationOptions &options,
                                          const BufferizationState &state,
                                          SmallVector<Value> &invocationStack) const {
    FailureOr<BufferLikeType> from =
        bufferization::getBufferType(sourceOf(op), options, state, invocationStack);
    if (failed(from))
      return failure();
    return cast<BufferLikeType>(idr::unrestricted(*from));
  }

  LogicalResult bufferize(Operation *op, RewriterBase &rewriter,
                          const BufferizationOptions &options, BufferizationState &state) const {
    FailureOr<Value> buffer = getBuffer(rewriter, sourceOf(op), options, state);
    if (failed(buffer))
      return failure();
    replaceOpWithNewBufferizedOp<idr::CarrierOp>(rewriter, op, *buffer,
                                                 cast<idr::CarrierOp>(op).getLifetime());
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
    return idr::bufferize::cellType(cast<TensorLikeType>(value.getType()));
  }

  LogicalResult bufferize(Operation *op, RewriterBase &rewriter, const BufferizationOptions &,
                          BufferizationState &) const {
    replaceOpWithNewBufferizedOp<ub::PoisonOp>(
        rewriter, op, idr::bufferize::cellType(cast<TensorLikeType>(op->getResult(0).getType())));
    return success();
  }
};

} // namespace

void idr::bufferize::attachViewModels(MLIRContext *ctx) {
  idr::ArrayTieShapeOp::attachInterface<TieShapeModel>(*ctx);
  idr::CarrierOp::attachInterface<CarrierModel>(*ctx);
}

void idr::bufferize::attachPoisonModel(MLIRContext *ctx) {
  ub::PoisonOp::attachInterface<PoisonModel>(*ctx);
}
