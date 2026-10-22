// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Region ops whose results are what their regions give (idr.match,
// idr.match_lit, idr.memo.run) and the terminator that gives it
// (idr.yield): one model each, read off RegionBranchOpInterface, so no
// model lists what a terminator forwards or which case yields.
//
// A cell's field holds its buffer from the frontend on: idr.con takes one
// through upstream's to_buffer, a release One-Shot already models, and
// idr.field gives one that upstream's to_tensor puts back in the tensor
// world, writable only where the cell is exclusive. So no idr op that
// stores or reads a cell needs a model of its own here. A value a
// terminator gives that goes to no result of its parent (a memo cell's
// forced value) moves into memory the parent holds: a release.
#include "idr/Transforms/BufferizeModels.h"

#include "mlir/Dialect/Bufferization/IR/Bufferization.h"
#include "mlir/Dialect/Bufferization/Transforms/Bufferize.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <optional>

using namespace mlir;
using namespace mlir::bufferization;

namespace {

// The operands of the terminator of `region` that go to the results of the
// op that holds it, in order, when the region returns there: a region that
// never returns, or a default region that is empty, gives none.
std::optional<OperandRange> givenBy(Region &region) {
  if (region.empty())
    return std::nullopt;
  auto end = dyn_cast<RegionBranchTerminatorOpInterface>(region.front().getTerminator());
  if (!end)
    return std::nullopt;
  return end.getSuccessorOperands(RegionSuccessor(region.getParentOp()));
}

// The operands that give an op's result `result`: one per region that
// returns.
SmallVector<OpOperand *> giving(Operation *op, OpResult result) {
  SmallVector<OpOperand *> operands;
  for (Region &region : op->getRegions())
    if (std::optional<OperandRange> given = givenBy(region))
      operands.push_back(&region.front().getTerminator()->getOpOperand(
          given->getBeginOperandIndex() + result.getResultNumber()));
  return operands;
}

// A region op whose every result is one of the values its regions give,
// the very buffer when only one region gives one; its regions run once at
// most, never again after one has run.
template <typename Op>
struct GivenModel : BufferizableOpInterface::ExternalModel<GivenModel<Op>, Op> {
  AliasingOpOperandList getAliasingOpOperands(Operation *op, Value value,
                                              const AnalysisState &) const {
    auto result = dyn_cast<OpResult>(value);
    if (!result)
      return {};
    SmallVector<OpOperand *> operands = giving(op, result);
    AliasingOpOperandList aliases;
    for (OpOperand *operand : operands)
      aliases.addAlias({operand, BufferRelation::Equivalent, /*isDefinite=*/operands.size() == 1});
    return aliases;
  }

  bool isWritable(Operation *, Value value, const AnalysisState &) const {
    return isa<OpResult>(value);
  }

  bool isRepetitiveRegion(Operation *, unsigned) const { return false; }

  FailureOr<BufferLikeType> getBufferType(Operation *op, Value value,
                                          const BufferizationOptions &options,
                                          const BufferizationState &state,
                                          SmallVector<Value> &invocationStack) const {
    auto result = dyn_cast<OpResult>(value);
    if (!result)
      return idr::bufferize::cellType(cast<TensorLikeType>(value.getType()));
    std::optional<BufferLikeType> joined;
    for (OpOperand *operand : giving(op, result)) {
      Value given = operand->get();
      FailureOr<BufferLikeType> type =
          isa<BufferLikeType>(given.getType())
              ? FailureOr<BufferLikeType>(cast<BufferLikeType>(given.getType()))
              : bufferization::getBufferType(given, options, state, invocationStack);
      if (failed(type))
        return failure();
      if (!joined || *joined == *type) {
        joined = *type;
        continue;
      }
      FailureOr<BufferLikeType> reconciled =
          options.reconcileBufferTypeMismatchFn(*joined, *type, options);
      if (failed(reconciled))
        return op->emitError("internal error: idr-bufferize: the regions of ")
               << op->getName() << " give arrays of buffer types that do not reconcile";
      joined = *reconciled;
    }
    // No region gives one (every one ends the run): the result is never
    // read.
    if (!joined)
      return idr::bufferize::cellType(cast<TensorLikeType>(value.getType()));
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

// The terminator that gives a region op's results: a value it gives to a
// result is that result, never copied into a new buffer where its own would
// do; a value it gives to no result moves into memory its parent holds.
template <typename Op>
struct GivingModel : BufferizableOpInterface::ExternalModel<GivingModel<Op>, Op> {
  // The parent's result the operand gives, if it gives one.
  static std::optional<OpResult> resultOf(Operation *op, OpOperand &operand) {
    std::optional<OperandRange> given = givenBy(*op->getParentRegion());
    if (!given)
      return std::nullopt;
    unsigned first = given->getBeginOperandIndex();
    unsigned at = operand.getOperandNumber();
    if (at < first || at >= first + given->size())
      return std::nullopt;
    return op->getParentOp()->getResult(at - first);
  }

  bool bufferizesToMemoryRead(Operation *, OpOperand &, const AnalysisState &) const {
    return true;
  }
  bool bufferizesToMemoryWrite(Operation *op, OpOperand &operand, const AnalysisState &) const {
    return !resultOf(op, operand).has_value();
  }
  AliasingValueList getAliasingValues(Operation *op, OpOperand &operand,
                                      const AnalysisState &) const {
    std::optional<OpResult> result = resultOf(op, operand);
    if (!result)
      return {};
    return {{*result, BufferRelation::Equivalent,
             /*isDefinite=*/giving(op->getParentOp(), *result).size() == 1}};
  }
  bool mustBufferizeInPlace(Operation *op, OpOperand &operand, const AnalysisState &) const {
    return resultOf(op, operand).has_value();
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
      std::optional<OpResult> result = resultOf(op, operand);
      if (!result) {
        FailureOr<Value> buffer = idr::bufferize::cellBuffer(rewriter, value, options, state);
        if (failed(buffer))
          return failure();
        values.push_back(*buffer);
        continue;
      }
      FailureOr<Value> buffer = getBuffer(rewriter, value, options, state);
      if (failed(buffer))
        return failure();
      FailureOr<BufferLikeType> type = bufferization::getBufferType(*result, options, state);
      if (failed(type))
        return failure();
      if (buffer->getType() != *type) {
        buffer = options.castFn(rewriter, op->getLoc(), *type, *buffer);
        if (failed(buffer))
          return failure();
      }
      values.push_back(*buffer);
    }
    replaceOpWithNewBufferizedOp<Op>(rewriter, op, values);
    return success();
  }
};

} // namespace

void idr::bufferize::attachDataModels(MLIRContext *ctx) {
  idr::MatchOp::attachInterface<GivenModel<idr::MatchOp>>(*ctx);
  idr::MatchLitOp::attachInterface<GivenModel<idr::MatchLitOp>>(*ctx);
  idr::MemoRunOp::attachInterface<GivenModel<idr::MemoRunOp>>(*ctx);
  idr::YieldOp::attachInterface<GivingModel<idr::YieldOp>>(*ctx);
}
