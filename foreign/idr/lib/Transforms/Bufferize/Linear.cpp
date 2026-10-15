// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The linear positions: idr.lin.enter is a release, idr.lin.use a writable
// root, and every link of a linear thread is written in place.
//
// A linear binder does not imply unique ownership, so the grade assumes
// nothing: entering a linear type reads and writes the tensor's buffer, and
// One-Shot copies there exactly when that buffer is read again afterwards
// or is not writable (a constant, an array read from the heap). Past the
// release, the buffer is the thread's alone, so the use that takes it out
// again starts a buffer the thread may write.
//
// The in-place promise of a linear array is that every write of its thread
// is in place. Inside a function the thread is a chain of destinations,
// which the analysis puts in place because nothing reads an old version;
// at the thread's boundaries (a call, a block, a cell) the chain passes
// through an entry whose buffer a use began, a link, which must bufferize
// in place. A copy there would be the compiler's, never the program's,
// since a linear array aliases nothing by the library's construction. An
// entry no use began (a fresh array, or an array thawed) is a thread's
// head, a plain release, which copies when its meaning does.
#include "idr/Transforms/BufferizeModels.h"

#include "mlir/Dialect/Bufferization/IR/Bufferization.h"

using namespace mlir;
using namespace mlir::bufferization;

bool idr::bufferize::isLink(idr::LinEnterOp enter, const AnalysisState &state) {
  // Through the destinations of the writes, which are the same buffer, and
  // no further: a slice of a thread is not the thread's buffer.
  TraversalConfig config;
  config.alwaysIncludeLeaves = false;
  config.followEquivalentOnly = true;
  return !state
              .findValueInReverseUseDefChain(
                  &enter->getOpOperand(0),
                  [](Value value) { return static_cast<bool>(value.getDefiningOp<LinUseOp>()); },
                  config)
              .empty();
}

namespace {

struct EnterModel : BufferizableOpInterface::ExternalModel<EnterModel, idr::LinEnterOp> {
  bool bufferizesToMemoryRead(Operation *, OpOperand &, const AnalysisState &) const {
    return true;
  }
  bool bufferizesToMemoryWrite(Operation *, OpOperand &, const AnalysisState &) const {
    return true;
  }
  // It makes no tensor: the linear value is the thread's from here on.
  AliasingValueList getAliasingValues(Operation *, OpOperand &, const AnalysisState &) const {
    return {};
  }

  bool mustBufferizeInPlace(Operation *op, OpOperand &, const AnalysisState &state) const {
    return idr::bufferize::isLink(cast<idr::LinEnterOp>(op), state);
  }

  // A thread's buffer is a whole cell, so a link never reallocates; a head
  // entered from a slice gets a cell of its own.
  LogicalResult bufferize(Operation *op, RewriterBase &rewriter,
                          const BufferizationOptions &options, BufferizationState &state) const {
    auto enter = cast<idr::LinEnterOp>(op);
    FailureOr<Value> buffer =
        idr::bufferize::cellBuffer(rewriter, enter.getValue(), options, state);
    if (failed(buffer))
      return failure();
    rewriter.replaceOpWithNewOp<idr::LinEnterOp>(enter, idr::linear(buffer->getType()), *buffer);
    return success();
  }
};

struct UseModel : BufferizableOpInterface::ExternalModel<UseModel, idr::LinUseOp> {
  // A root of its own: the release that made the linear value gave its
  // buffer to the thread.
  AliasingOpOperandList getAliasingOpOperands(Operation *, Value, const AnalysisState &) const {
    return {};
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
    auto use = cast<idr::LinUseOp>(op);
    replaceOpWithNewBufferizedOp<idr::LinUseOp>(
        rewriter, op, idr::bufferize::bufferType(cast<RankedTensorType>(use.getType())),
        use.getLinear());
    return success();
  }
};

} // namespace

void idr::bufferize::attachLinearModels(MLIRContext *ctx) {
  idr::LinEnterOp::attachInterface<EnterModel>(*ctx);
  idr::LinUseOp::attachInterface<UseModel>(*ctx);
}
