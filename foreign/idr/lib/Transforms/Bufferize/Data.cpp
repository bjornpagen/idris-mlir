// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Cells and matches: idr.con stores a tensor into a cell and a memo cell's
// force (idr.memo.run) into the memo cell, through its idr.array.yield,
// idr.field and the force's captures read one from the heap, and
// idr.match, idr.match_lit and idr.yield join the arrays their cases give.
//
// A store into a cell is a release, as an entry into a linear type is:
// whatever else still reads the buffer makes One-Shot copy it there, and
// the cell holds a buffer no one else writes. A read from the heap gives a
// buffer others may read too (the cell may be shared), so it is not
// writable: a write to it copies first, as upstream's to_tensor with
// `restrict` and without `writable` says. A linear array read from a cell
// is no tensor here; its use makes the writable root, since the store was
// its release. Every buffer a cell holds is a whole cell, so the types of
// what is stored and read are the tensors' cell buffers.
#include "idr/Transforms/BufferizeModels.h"

#include "mlir/Dialect/Bufferization/IR/Bufferization.h"
#include "mlir/Dialect/Bufferization/Transforms/Bufferize.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <optional>

using namespace mlir;
using namespace mlir::bufferization;

namespace {

// idr.con: each tensor operand is stored in a cell.
template <typename Store>
struct StoreModel : BufferizableOpInterface::ExternalModel<StoreModel<Store>, Store> {
  bool bufferizesToMemoryRead(Operation *, OpOperand &, const AnalysisState &) const {
    return true;
  }
  bool bufferizesToMemoryWrite(Operation *, OpOperand &, const AnalysisState &) const {
    return true;
  }
  AliasingValueList getAliasingValues(Operation *, OpOperand &, const AnalysisState &) const {
    return {};
  }

  LogicalResult bufferize(Operation *op, RewriterBase &rewriter,
                          const BufferizationOptions &options, BufferizationState &state) const {
    for (OpOperand &field : op->getOpOperands()) {
      if (!isa<TensorLikeType>(field.get().getType()))
        continue;
      FailureOr<Value> buffer = idr::bufferize::cellBuffer(rewriter, field.get(), options, state);
      if (failed(buffer))
        return failure();
      rewriter.modifyOpInPlace(op, [&] { field.set(*buffer); });
    }
    return success();
  }
};

// idr.field: a tensor read from the heap.
struct HeapReadModel : BufferizableOpInterface::ExternalModel<HeapReadModel, idr::FieldOp> {
  AliasingOpOperandList getAliasingOpOperands(Operation *, Value, const AnalysisState &) const {
    return {};
  }
  bool isWritable(Operation *, Value, const AnalysisState &) const { return false; }
  bool bufferizesToAllocation(Operation *, Value) const { return false; }

  FailureOr<BufferLikeType> getBufferType(Operation *, Value value, const BufferizationOptions &,
                                          const BufferizationState &,
                                          SmallVector<Value> &) const {
    return idr::bufferize::cellType(value);
  }

  LogicalResult bufferize(Operation *op, RewriterBase &rewriter, const BufferizationOptions &,
                          BufferizationState &) const {
    Operation *bufferized = rewriter.clone(*op);
    for (OpResult result : bufferized->getResults())
      result.setType(idr::bufferize::heldType(result.getType()));
    replaceOpWithBufferizedValues(rewriter, op, bufferized->getResults());
    return success();
  }
};

// The regions of a match that end in idr.yield; a case that crashes ends in
// ub.unreachable and gives no value, and an exhaustive match's default
// region is empty and never runs.
SmallVector<idr::YieldOp> yields(Operation *match) {
  SmallVector<idr::YieldOp> found;
  for (Region &region : match->getRegions())
    if (!region.empty())
      if (auto yield = dyn_cast<idr::YieldOp>(region.front().getTerminator()))
        found.push_back(yield);
  return found;
}

// idr.match and idr.match_lit: each result is one of the arrays its cases
// yield, the very buffer when only one case yields. A bound field is read
// from the scrutinee, a read from the heap.
template <typename Match>
struct MatchModel : BufferizableOpInterface::ExternalModel<MatchModel<Match>, Match> {
  AliasingOpOperandList getAliasingOpOperands(Operation *op, Value value,
                                              const AnalysisState &) const {
    auto result = dyn_cast<OpResult>(value);
    if (!result)
      return {};
    SmallVector<idr::YieldOp> ends = yields(op);
    AliasingOpOperandList aliases;
    for (idr::YieldOp yield : ends)
      aliases.addAlias({&yield->getOpOperand(result.getResultNumber()),
                        BufferRelation::Equivalent, /*isDefinite=*/ends.size() == 1});
    return aliases;
  }

  bool isWritable(Operation *, Value value, const AnalysisState &) const {
    return isa<OpResult>(value);
  }

  FailureOr<BufferLikeType> getBufferType(Operation *op, Value value,
                                          const BufferizationOptions &options,
                                          const BufferizationState &state,
                                          SmallVector<Value> &invocationStack) const {
    auto result = dyn_cast<OpResult>(value);
    if (!result)
      return idr::bufferize::cellType(value);
    std::optional<BufferLikeType> joined;
    for (idr::YieldOp yield : yields(op)) {
      Value yielded = yield->getOperand(result.getResultNumber());
      FailureOr<BufferLikeType> type =
          isa<BufferLikeType>(yielded.getType())
              ? FailureOr<BufferLikeType>(cast<BufferLikeType>(yielded.getType()))
              : bufferization::getBufferType(yielded, options, state, invocationStack);
      if (failed(type))
        return failure();
      if (!joined || *joined == *type) {
        joined = *type;
        continue;
      }
      FailureOr<BufferLikeType> reconciled =
          options.reconcileBufferTypeMismatchFn(*joined, *type, options);
      if (failed(reconciled))
        return op->emitError("internal error: idr-bufferize: the cases of a match yield arrays "
                             "of buffer types that do not reconcile");
      joined = *reconciled;
    }
    // No case yields (every one crashes): the result is never read.
    if (!joined)
      return idr::bufferize::cellType(value);
    return *joined;
  }

  LogicalResult bufferize(Operation *op, RewriterBase &rewriter,
                          const BufferizationOptions &options, BufferizationState &state) const {
    SmallVector<Type> types;
    for (OpResult result : op->getResults()) {
      if (!isa<TensorLikeType>(result.getType())) {
        types.push_back(result.getType());
        continue;
      }
      FailureOr<BufferLikeType> type = bufferization::getBufferType(result, options, state);
      if (failed(type))
        return failure();
      types.push_back(*type);
    }
    Operation *bufferized = rewriter.cloneWithoutRegions(*op);
    for (auto [result, type] : llvm::zip_equal(bufferized->getResults(), types))
      result.setType(type);
    for (auto [from, to] : llvm::zip_equal(op->getRegions(), bufferized->getRegions()))
      rewriter.inlineRegionBefore(from, to, to.end());
    for (Region &region : bufferized->getRegions())
      if (!region.empty() &&
          failed(bufferizeBlockSignature(&region.front(), rewriter, options, state)))
        return failure();
    replaceOpWithBufferizedValues(rewriter, op, bufferized->getResults());
    return success();
  }
};

// The end of a case: its values are the match's, never copied into a new
// buffer where the case's own would do.
struct YieldModel : BufferizableOpInterface::ExternalModel<YieldModel, idr::YieldOp> {
  bool bufferizesToMemoryRead(Operation *, OpOperand &, const AnalysisState &) const {
    return true;
  }
  bool bufferizesToMemoryWrite(Operation *, OpOperand &, const AnalysisState &) const {
    return false;
  }
  AliasingValueList getAliasingValues(Operation *op, OpOperand &operand,
                                      const AnalysisState &) const {
    Operation *match = op->getParentOp();
    return {{match->getResult(operand.getOperandNumber()), BufferRelation::Equivalent,
             /*isDefinite=*/yields(match).size() == 1}};
  }
  bool mustBufferizeInPlace(Operation *, OpOperand &, const AnalysisState &) const {
    return true;
  }

  LogicalResult bufferize(Operation *op, RewriterBase &rewriter,
                          const BufferizationOptions &options, BufferizationState &state) const {
    SmallVector<Value> values;
    for (OpOperand &operand : op->getOpOperands()) {
      Value value = operand.get();
      if (!isa<TensorLikeType>(value.getType())) {
        values.push_back(value);
        continue;
      }
      FailureOr<Value> buffer = getBuffer(rewriter, value, options, state);
      if (failed(buffer))
        return failure();
      FailureOr<BufferLikeType> type = bufferization::getBufferType(
          op->getParentOp()->getResult(operand.getOperandNumber()), options, state);
      if (failed(type))
        return failure();
      if (buffer->getType() != *type) {
        buffer = options.castFn(rewriter, op->getLoc(), *type, *buffer);
        if (failed(buffer))
          return failure();
      }
      values.push_back(*buffer);
    }
    replaceOpWithNewBufferizedOp<idr::YieldOp>(rewriter, op, values);
    return success();
  }
};

// idr.memo.run: a capture is a tensor read from the heap, as idr.field
// reads one, and each result is the array the region gives after the
// value, which its yield stores.
struct MemoRunModel : BufferizableOpInterface::ExternalModel<MemoRunModel, idr::MemoRunOp> {
  // The yield's value that `result` is, after the one that moves in.
  static OpOperand *forwarded(Operation *op, OpResult result) {
    auto yield = dyn_cast<idr::ArrayYieldOp>(op->getRegion(0).front().getTerminator());
    if (!yield)
      return nullptr;
    return &yield->getOpOperand(result.getResultNumber() + 1);
  }

  AliasingOpOperandList getAliasingOpOperands(Operation *op, Value value,
                                              const AnalysisState &) const {
    auto result = dyn_cast<OpResult>(value);
    OpOperand *given = result ? forwarded(op, result) : nullptr;
    if (!given)
      return {};
    return {{given, BufferRelation::Equivalent, /*isDefinite=*/true}};
  }

  bool isWritable(Operation *, Value value, const AnalysisState &) const {
    return isa<OpResult>(value);
  }

  FailureOr<BufferLikeType> getBufferType(Operation *op, Value value,
                                          const BufferizationOptions &options,
                                          const BufferizationState &state,
                                          SmallVector<Value> &invocationStack) const {
    auto result = dyn_cast<OpResult>(value);
    OpOperand *given = result ? forwarded(op, result) : nullptr;
    // A capture, or the result of a region that never returns, which is
    // never read.
    if (!given)
      return idr::bufferize::cellType(value);
    Value yielded = given->get();
    if (auto type = dyn_cast<BufferLikeType>(yielded.getType()))
      return type;
    return bufferization::getBufferType(yielded, options, state, invocationStack);
  }

  LogicalResult bufferize(Operation *op, RewriterBase &rewriter,
                          const BufferizationOptions &options, BufferizationState &state) const {
    SmallVector<Type> types;
    for (OpResult result : op->getResults()) {
      if (!isa<TensorLikeType>(result.getType())) {
        types.push_back(result.getType());
        continue;
      }
      FailureOr<BufferLikeType> type = bufferization::getBufferType(result, options, state);
      if (failed(type))
        return failure();
      types.push_back(*type);
    }
    Operation *bufferized = rewriter.cloneWithoutRegions(*op);
    for (auto [result, type] : llvm::zip_equal(bufferized->getResults(), types))
      result.setType(type);
    rewriter.inlineRegionBefore(op->getRegion(0), bufferized->getRegion(0),
                                bufferized->getRegion(0).end());
    if (failed(bufferizeBlockSignature(&bufferized->getRegion(0).front(), rewriter, options,
                                       state)))
      return failure();
    replaceOpWithBufferizedValues(rewriter, op, bufferized->getResults());
    return success();
  }
};

// The end of a force's region, the one idr.array.yield that may yield a
// tensor here (an array op's yield is in a loop by now, and an update's
// yields an element, never an array): its
// value is stored in the memo cell, a release as idr.con's fields are, and
// the values after it are the force's results, never copied into a new
// buffer where the region's own would do.
struct MemoYieldModel : BufferizableOpInterface::ExternalModel<MemoYieldModel, idr::ArrayYieldOp> {
  bool bufferizesToMemoryRead(Operation *, OpOperand &, const AnalysisState &) const {
    return true;
  }
  bool bufferizesToMemoryWrite(Operation *, OpOperand &operand, const AnalysisState &) const {
    return operand.getOperandNumber() == 0;
  }
  AliasingValueList getAliasingValues(Operation *op, OpOperand &operand,
                                      const AnalysisState &) const {
    if (operand.getOperandNumber() == 0)
      return {};
    return {{op->getParentOp()->getResult(operand.getOperandNumber() - 1),
             BufferRelation::Equivalent, /*isDefinite=*/true}};
  }
  bool mustBufferizeInPlace(Operation *, OpOperand &operand, const AnalysisState &) const {
    return operand.getOperandNumber() != 0;
  }

  LogicalResult bufferize(Operation *op, RewriterBase &rewriter,
                          const BufferizationOptions &options, BufferizationState &state) const {
    SmallVector<Value> values;
    for (OpOperand &operand : op->getOpOperands()) {
      Value value = operand.get();
      if (!isa<TensorLikeType>(value.getType())) {
        values.push_back(value);
        continue;
      }
      if (operand.getOperandNumber() == 0) {
        FailureOr<Value> buffer = idr::bufferize::cellBuffer(rewriter, value, options, state);
        if (failed(buffer))
          return failure();
        values.push_back(*buffer);
        continue;
      }
      FailureOr<Value> buffer = getBuffer(rewriter, value, options, state);
      if (failed(buffer))
        return failure();
      FailureOr<BufferLikeType> type = bufferization::getBufferType(
          op->getParentOp()->getResult(operand.getOperandNumber() - 1), options, state);
      if (failed(type))
        return failure();
      if (buffer->getType() != *type) {
        buffer = options.castFn(rewriter, op->getLoc(), *type, *buffer);
        if (failed(buffer))
          return failure();
      }
      values.push_back(*buffer);
    }
    replaceOpWithNewBufferizedOp<idr::ArrayYieldOp>(rewriter, op, values);
    return success();
  }
};

} // namespace

void idr::bufferize::attachDataModels(MLIRContext *ctx) {
  idr::ConOp::attachInterface<StoreModel<idr::ConOp>>(*ctx);
  idr::MemoRunOp::attachInterface<MemoRunModel>(*ctx);
  idr::ArrayYieldOp::attachInterface<MemoYieldModel>(*ctx);
  idr::FieldOp::attachInterface<HeapReadModel>(*ctx);
  idr::MatchOp::attachInterface<MatchModel<idr::MatchOp>>(*ctx);
  idr::MatchLitOp::attachInterface<MatchModel<idr::MatchLitOp>>(*ctx);
  idr::YieldOp::attachInterface<YieldModel>(*ctx);
}
