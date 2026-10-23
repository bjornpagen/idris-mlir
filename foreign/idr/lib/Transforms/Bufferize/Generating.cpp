// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The generating set (idr.array.tabulate, idr.array.fold_last,
// idr.array.scan_last), the yield that ends their regions, and the reads
// of an element and of an extent that give their array back.
//
// A generating op is destination-style, so upstream's DPS model says most
// of it: each destination is written and is its result. What the model
// cannot know it says: a tabulation's destination and a scan's are written
// and never read, so One-Shot keeps no undefined contents alive and copies
// nothing it would not need to; a fold reads its destination, its first
// accumulators; a scan's inputs are read and written never. Bufferized, the
// op is the same op on the destinations' buffers, giving nothing, its
// region moved: it stays an op until right before the lowering, where
// upstream's lowerToLoopsUsingSCFForOp makes it its loops, and counting
// meets it on buffers through its flow and effects in between.
#include "idr/IR/Grades.h"
#include "idr/Transforms/BufferizeModels.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Bufferization/IR/Bufferization.h"
#include "mlir/Dialect/Bufferization/IR/DstBufferizableOpInterfaceImpl.h"
#include "mlir/Dialect/Bufferization/Transforms/Bufferize.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"

using namespace mlir;
using namespace mlir::bufferization;

namespace {

// How a generating op reads its destinations: a fold its first
// accumulators there, a tabulation and a scan nothing, which they only
// write. Its other operands (a scan's inputs, a length) are read.
enum class Reads { Destinations, Nothing };

template <Reads reads>
bool readsOperand(Operation *op, OpOperand &operand) {
  if (!cast<DestinationStyleOpInterface>(op).isDpsInit(&operand))
    return true;
  return reads == Reads::Destinations;
}

template <typename Op, Reads reads>
struct GeneratingModel
    : DstBufferizableOpInterfaceExternalModel<GeneratingModel<Op, reads>, Op> {
  bool bufferizesToMemoryRead(Operation *op, OpOperand &operand, const AnalysisState &) const {
    return readsOperand<reads>(op, operand);
  }

  // An index or an accumulator the region binds; a result is its
  // destination's buffer.
  FailureOr<BufferLikeType> getBufferType(Operation *op, Value value,
                                          const BufferizationOptions &options,
                                          const BufferizationState &state,
                                          SmallVector<Value> &invocationStack) const {
    if (auto result = dyn_cast<OpResult>(value)) {
      OpOperand *out = cast<DestinationStyleOpInterface>(op).getTiedOpOperand(result);
      return bufferization::getBufferType(out->get(), options, state, invocationStack);
    }
    return idr::bufferize::cellType(cast<TensorLikeType>(value.getType()));
  }

  // The same op on the buffers of its operands, giving nothing, its region
  // moved and its block's tensors their cells' buffers; each result is its
  // destination's buffer.
  LogicalResult bufferize(Operation *op, RewriterBase &rewriter,
                          const BufferizationOptions &options, BufferizationState &state) const {
    auto dps = cast<DestinationStyleOpInterface>(op);
    SmallVector<Value> operands;
    SmallVector<Value> outs;
    for (OpOperand &operand : op->getOpOperands()) {
      Value value = operand.get();
      if (!isa<TensorLikeType>(value.getType())) {
        operands.push_back(value);
        continue;
      }
      FailureOr<Value> buffer = dps.isDpsInit(&operand)
                                    ? idr::bufferize::cellBuffer(rewriter, value, options, state)
                                    : getBuffer(rewriter, value, options, state);
      if (failed(buffer))
        return failure();
      operands.push_back(*buffer);
      if (dps.isDpsInit(&operand))
        outs.push_back(*buffer);
    }
    rewriter.setInsertionPoint(op);
    OperationState made(op->getLoc(), op->getName());
    made.addOperands(operands);
    made.propertiesAttr = op->getPropertiesAsAttribute();
    made.addRegion();
    Operation *bufferized = rewriter.create(made);
    rewriter.inlineRegionBefore(op->getRegion(0), bufferized->getRegion(0),
                                bufferized->getRegion(0).end());
    if (failed(bufferizeBlockSignature(&bufferized->getRegion(0).front(), rewriter, options,
                                       state)))
      return failure();
    replaceOpWithBufferizedValues(rewriter, op, outs);
    return success();
  }
};

// The end of a step: each value is read into its destination's slots there,
// which the lowering places it in, never a buffer the destination becomes.
// A cell crosses as a whole cell's buffer.
struct YieldModel : BufferizableOpInterface::ExternalModel<YieldModel, idr::ArrayYieldOp> {
  bool bufferizesToMemoryRead(Operation *, OpOperand &, const AnalysisState &) const {
    return true;
  }
  bool bufferizesToMemoryWrite(Operation *, OpOperand &, const AnalysisState &) const {
    return false;
  }
  AliasingValueList getAliasingValues(Operation *, OpOperand &, const AnalysisState &) const {
    return {};
  }

  LogicalResult bufferize(Operation *op, RewriterBase &rewriter,
                          const BufferizationOptions &options, BufferizationState &state) const {
    SmallVector<Value> values;
    for (Value value : op->getOperands()) {
      if (!isa<TensorLikeType>(value.getType())) {
        values.push_back(value);
        continue;
      }
      FailureOr<Value> buffer = idr::bufferize::cellBuffer(rewriter, value, options, state);
      if (failed(buffer))
        return failure();
      values.push_back(*buffer);
    }
    replaceOpWithNewBufferizedOp<idr::ArrayYieldOp>(rewriter, op, values);
    return success();
  }
};

// The read of an element that gives its array back: it reads the array and
// writes nothing, and the array it gives is the array's buffer.
struct ReadModel : BufferizableOpInterface::ExternalModel<ReadModel, idr::ArrayReadOp> {
  bool bufferizesToMemoryRead(Operation *, OpOperand &, const AnalysisState &) const {
    return true;
  }
  bool bufferizesToMemoryWrite(Operation *, OpOperand &, const AnalysisState &) const {
    return false;
  }
  AliasingValueList getAliasingValues(Operation *op, OpOperand &operand,
                                      const AnalysisState &) const {
    if (operand.getOperandNumber() != 0)
      return {};
    return {{cast<idr::ArrayReadOp>(op).getAfter(), BufferRelation::Equivalent,
             /*isDefinite=*/true}};
  }

  FailureOr<BufferLikeType> getBufferType(Operation *op, Value, const BufferizationOptions &options,
                                          const BufferizationState &state,
                                          SmallVector<Value> &invocationStack) const {
    return bufferization::getBufferType(cast<idr::ArrayReadOp>(op).getArray(), options, state,
                                        invocationStack);
  }

  LogicalResult bufferize(Operation *op, RewriterBase &rewriter,
                          const BufferizationOptions &options, BufferizationState &state) const {
    auto read = cast<idr::ArrayReadOp>(op);
    FailureOr<Value> buffer = getBuffer(rewriter, read.getArray(), options, state);
    if (failed(buffer))
      return failure();
    Value element = memref::LoadOp::create(rewriter, read.getLoc(), *buffer, read.getIndices());
    replaceOpWithBufferizedValues(rewriter, op, {element, *buffer});
    return success();
  }
};

// The read of an extent that gives its array back: it reads the shape, no
// element, and writes nothing; the array it gives is the array's buffer and
// the extent the buffer's dimension, the small of the word it is. A small
// has no cell, so it is static data, used many; it is given at the
// extent's own type, which every use of the extent was written for.
struct ExtentModel : BufferizableOpInterface::ExternalModel<ExtentModel, idr::ArrayExtentOp> {
  bool bufferizesToMemoryRead(Operation *, OpOperand &, const AnalysisState &) const {
    return false;
  }
  bool bufferizesToMemoryWrite(Operation *, OpOperand &, const AnalysisState &) const {
    return false;
  }
  AliasingValueList getAliasingValues(Operation *op, OpOperand &, const AnalysisState &) const {
    return {{cast<idr::ArrayExtentOp>(op).getAfter(), BufferRelation::Equivalent,
             /*isDefinite=*/true}};
  }

  FailureOr<BufferLikeType> getBufferType(Operation *op, Value, const BufferizationOptions &options,
                                          const BufferizationState &state,
                                          SmallVector<Value> &invocationStack) const {
    return bufferization::getBufferType(cast<idr::ArrayExtentOp>(op).getArray(), options, state,
                                        invocationStack);
  }

  LogicalResult bufferize(Operation *op, RewriterBase &rewriter,
                          const BufferizationOptions &options, BufferizationState &state) const {
    auto extent = cast<idr::ArrayExtentOp>(op);
    FailureOr<Value> buffer = getBuffer(rewriter, extent.getArray(), options, state);
    if (failed(buffer))
      return failure();
    Location loc = extent.getLoc();
    Value size =
        memref::DimOp::create(rewriter, loc, *buffer, static_cast<int64_t>(extent.getAxis()));
    Value word = arith::IndexCastUIOp::create(rewriter, loc, rewriter.getI64Type(), size);
    Type type = extent.getExtent().getType();
    Type held =
        idr::graded(idr::Grade{idr::Uses::Many, idr::Hold::staticData()}, idr::unrestricted(type));
    Value small = idr::BigSmallOp::create(rewriter, loc, held, word);
    replaceOpWithBufferizedValues(rewriter, op, {idr::heldAs(rewriter, loc, small, type), *buffer});
    return success();
  }
};

} // namespace

void idr::bufferize::attachGeneratingModels(MLIRContext *ctx) {
  idr::ArrayTabulateOp::attachInterface<
      GeneratingModel<idr::ArrayTabulateOp, Reads::Nothing>>(*ctx);
  idr::ArrayFoldLastOp::attachInterface<
      GeneratingModel<idr::ArrayFoldLastOp, Reads::Destinations>>(*ctx);
  idr::ArrayScanLastOp::attachInterface<
      GeneratingModel<idr::ArrayScanLastOp, Reads::Nothing>>(*ctx);
  idr::ArrayYieldOp::attachInterface<YieldModel>(*ctx);
  idr::ArrayReadOp::attachInterface<ReadModel>(*ctx);
  idr::ArrayExtentOp::attachInterface<ExtentModel>(*ctx);
}
