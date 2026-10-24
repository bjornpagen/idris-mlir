// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Grades: a graded tensor is a tensor to One-Shot, and an op that changes
// only a grade is its operand.
//
// A grade wraps any value, so whether a graded type is tensor-like is a
// fact of the instance, which upstream's per-instance check reads: tensor-
// like where its value is a tensor, buffer-like where it is a buffer, its
// buffer the value's cell buffer at the same grade. One-Shot then sees a
// linear array's wrapper, and every signature and region that carries one,
// as it sees a tensor, and bufferizes it itself.
//
// idr.lin.cast changes a value's uses, and idr.count.share forgets its
// claim, and neither anything of its contents: each is its operand, an
// equivalent alias that reads and writes nothing. A linear
// binder does not imply unique ownership, so the grade's uses decide
// nothing here. What a grade claims of its sharing does: the in-place
// promise and the local rule write their claims before bufferization, so a
// cell's grade may already claim its own cells unshared (`unique self`),
// which covers the storage of a buffer it holds, never the elements in it,
// and makes the array of that buffer writable, opened by idr.array.open or
// by the take before bufferization (idr.count.take_open). Every other
// write One-Shot decides by its own analysis, a thawed array's among them,
// and copies only where the array it came from is read again.
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

// An op whose result is its operand's value at another grade, by its trait.
template <class Op>
concept ChangesOnlyGrade =
    requires { requires Op::template hasTrait<idr::ResultCarriesOperand>(); };

// The value at the result's grade, its buffer the operand's: the same op
// made again on the buffer.
template <ChangesOnlyGrade Op>
struct GradeModel : BufferizableOpInterface::ExternalModel<GradeModel<Op>, Op> {
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
    replaceOpWithNewBufferizedOp<Op>(rewriter, op, *type, *buffer);
    return success();
  }
};

} // namespace

void idr::bufferize::attachGradedModels(MLIRContext *ctx) {
  idr::GradedType::attachInterface<GradedTensorLike, GradedBufferLike>(*ctx);
}

void idr::bufferize::attachLinearModels(MLIRContext *ctx) {
  idr::LinCastOp::attachInterface<GradeModel<idr::LinCastOp>>(*ctx);
  idr::CountShareOp::attachInterface<GradeModel<idr::CountShareOp>>(*ctx);
}
