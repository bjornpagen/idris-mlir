// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Grades: a graded tensor is a tensor to One-Shot, and the cast between
// grades is its operand.
//
// A grade wraps any value, so whether a graded type is tensor-like is a
// fact of the instance, which upstream's per-instance check reads: tensor-
// like where its value is a tensor, buffer-like where it is a buffer, its
// buffer the value's cell buffer at the same grade. One-Shot then sees a
// linear array's wrapper, and every signature and region that carries one,
// as it sees a tensor, and bufferizes it itself.
//
// idr.lin.cast changes a value's uses and nothing of its contents: it is
// its operand, an equivalent alias that reads and writes nothing. A linear
// binder does not imply unique ownership, so the grade's uses decide
// nothing here, and bufferization runs before any hold is decided, so no
// grade says a buffer is exclusive yet: One-Shot decides each write on a
// linear thread by its own analysis, a thawed array's among them, and
// copies only where the array it came from is read again.
#include "idr/Transforms/BufferizeModels.h"

#include "idr/IR/Grades.h"

#include "mlir/Dialect/Bufferization/IR/Bufferization.h"
#include "mlir/Dialect/Bufferization/IR/BufferizationTypeInterfaces.h"

using namespace mlir;
using namespace mlir::bufferization;

namespace {

// A graded tensor: tensor-like where its value is a tensor, its buffer a
// graded buffer of the same grade whose value is the tensor's buffer.
struct GradedTensorLike : TensorLikeType::ExternalModel<GradedTensorLike, idr::GradedType> {
  bool isTensorLike(Type type) const {
    return isa<RankedTensorType>(idr::unrestricted(type));
  }

  LogicalResult verifyCompatibleBufferType(Type type, BufferLikeType buffer,
                                           function_ref<InFlightDiagnostic()> emitError) const {
    auto tensor = cast<RankedTensorType>(idr::unrestricted(type));
    auto memref = dyn_cast<MemRefType>(idr::unrestricted(buffer));
    if (!memref || idr::gradeOf(buffer) != idr::gradeOf(type))
      return emitError() << "the buffer " << buffer << " of " << type
                         << " is not a buffer at the same grade";
    if (memref.getShape() != tensor.getShape() ||
        memref.getElementType() != tensor.getElementType())
      return emitError() << "the buffer " << buffer << " of " << type
                         << " has another shape or element";
    return success();
  }
};

// A graded buffer: buffer-like where its value is a buffer.
struct GradedBufferLike : BufferLikeType::ExternalModel<GradedBufferLike, idr::GradedType> {
  bool isBufferLike(Type type) const { return isa<BaseMemRefType>(idr::unrestricted(type)); }
};

struct CastModel : BufferizableOpInterface::ExternalModel<CastModel, idr::LinCastOp> {
  bool bufferizesToMemoryRead(Operation *, OpOperand &, const AnalysisState &) const {
    return false;
  }
  bool bufferizesToMemoryWrite(Operation *, OpOperand &, const AnalysisState &) const {
    return false;
  }
  AliasingValueList getAliasingValues(Operation *op, OpOperand &, const AnalysisState &) const {
    return {{op->getResult(0), BufferRelation::Equivalent, /*isDefinite=*/true}};
  }

  FailureOr<BufferLikeType> getBufferType(Operation *op, Value value,
                                          const BufferizationOptions &options,
                                          const BufferizationState &state,
                                          SmallVector<Value> &invocationStack) const {
    FailureOr<BufferLikeType> from =
        bufferization::getBufferType(op->getOperand(0), options, state, invocationStack);
    if (failed(from))
      return failure();
    // The same buffer at the result's grade.
    return cast<BufferLikeType>(idr::graded(idr::gradeOf(value.getType()),
                                            idr::unrestricted(*from)));
  }

  LogicalResult bufferize(Operation *op, RewriterBase &rewriter,
                          const BufferizationOptions &options, BufferizationState &state) const {
    FailureOr<Value> buffer = getBuffer(rewriter, op->getOperand(0), options, state);
    if (failed(buffer))
      return failure();
    FailureOr<BufferLikeType> type = bufferization::getBufferType(op->getResult(0), options, state);
    if (failed(type))
      return failure();
    replaceOpWithNewBufferizedOp<idr::LinCastOp>(rewriter, op, *type, *buffer);
    return success();
  }
};

} // namespace

void idr::bufferize::attachGradedModels(MLIRContext *ctx) {
  idr::GradedType::attachInterface<GradedTensorLike, GradedBufferLike>(*ctx);
}

void idr::bufferize::attachLinearModels(MLIRContext *ctx) {
  idr::LinCastOp::attachInterface<CastModel>(*ctx);
}
