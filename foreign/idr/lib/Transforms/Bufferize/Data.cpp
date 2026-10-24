// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Region ops whose results are what their regions give (idr.data.match,
// idr.lit.match, idr.memo.run, and idr.lifetime, the opener that acquires
// no memory, which a loan opens before bufferization and whose one region
// is bufferized in place) and the terminator that gives it (idr.yield):
// one model each, read off RegionBranchOpInterface, so no model lists what
// a terminator forwards or which case yields.
//
// A cell's field holds its buffer from the frontend on: idr.data.con takes
// one through upstream's to_buffer, a release One-Shot already models, and
// idr.array.open opens one as the array it is, taking the value that holds
// it, as does the take the in-place check makes before bufferization
// (idr.count.take_open), which opens each array its cell holds: so whether
// an array may be written in place is the claim of the value it is opened
// from, read here off the opening op's operand by one rule for both. So no
// other idr op that stores or reads a cell needs a model of its own here. A value a
// terminator gives that goes to no result of its parent (a memo cell's
// forced value) moves into memory the parent holds: a release.
#include "idr/Transforms/BufferizeModels.h"

#include "idr/IR/Grades.h"

#include "mlir/Dialect/Bufferization/IR/Bufferization.h"
#include "mlir/Dialect/Bufferization/Transforms/Bufferize.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <concepts>
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

// What a value must claim of its sharing for the buffer one of its fields
// holds to be its alone, which may then be written in place: its own cells
// unshared. That claim covers the storage of a buffer an own cell holds, so
// no other reference reaches its slots; it says nothing of the elements in
// them, and nothing need be said, since a write in place replaces what a
// slot holds (the element moving out with the buffer's reference) and never
// writes inside an element another holder may share.
constexpr idr::Unique bufferClaim = idr::Unique::Self;

// An op that opens the arrays a value's buffers are, taking the value: an
// opener of one field, or the take before bufferization.
template <typename Op>
concept OpensArraysOf = requires(Op op) {
  { op.getValue() } -> std::convertible_to<Value>;
};

// What such an op answers of each array it opens: a buffer of its own to
// the analysis, aliasing no tensor, and the only array of that buffer
// while it lives. It is writable where the value it is opened from makes
// bufferClaim, so One-Shot copies it only where the program reads it again
// and writes its slots, never the elements they hold; one opened from a
// value that claims less One-Shot copies before any write. Its buffer is a
// whole cell's, of the identity layout every field has, at the bare
// carrier upstream's ops take.
template <typename Model, OpensArraysOf Op>
struct OpensArrays : BufferizableOpInterface::ExternalModel<Model, Op> {
  bool isWritable(Operation *op, Value, const AnalysisState &) const {
    return idr::claims(cast<Op>(op).getValue().getType(), bufferClaim);
  }

  FailureOr<BufferLikeType> getBufferType(Operation *, Value value, const BufferizationOptions &,
                                          const BufferizationState &,
                                          SmallVector<Value> &) const {
    return idr::bufferize::cellType(cast<TensorLikeType>(value.getType()));
  }
};

// A field's buffer opened as the array it is: bufferized, it is the field
// read.
struct OpenModel : OpensArrays<OpenModel, idr::ArrayOpenOp> {
  LogicalResult bufferize(Operation *op, RewriterBase &rewriter, const BufferizationOptions &,
                          BufferizationState &) const {
    auto open = cast<idr::ArrayOpenOp>(op);
    Location loc = open.getLoc();
    Value read = idr::DataFieldOp::create(rewriter, loc, open.getValue(),
                                          static_cast<unsigned>(open.getIndex()));
    Value buffer = idr::heldAs(rewriter, loc, read,
                               idr::bufferize::cellType(cast<TensorLikeType>(open.getType())));
    replaceOpWithBufferizedValues(rewriter, op, buffer);
    return success();
  }
};

// The take before bufferization, its cell's arrays opened: bufferized, it
// is the take, each array the buffer the take moves out of its field, and
// every other result the take's own. Which results are arrays is the
// cell's, field by field.
struct TakeOpenModel : OpensArrays<TakeOpenModel, idr::CountTakeOpenOp> {
  LogicalResult bufferize(Operation *op, RewriterBase &rewriter, const BufferizationOptions &,
                          BufferizationState &) const {
    auto open = cast<idr::CountTakeOpenOp>(op);
    Location loc = open.getLoc();
    auto take = idr::CountTakeOp::create(rewriter, loc, open.getValue());
    SmallVector<Value> values{take.getToken()};
    for (auto [moved, given] : llvm::zip_equal(take.getFields(), open.getFields())) {
      auto array = dyn_cast<TensorLikeType>(given.getType());
      values.push_back(array ? idr::heldAs(rewriter, loc, moved, idr::bufferize::cellType(array))
                             : moved);
    }
    replaceOpWithBufferizedValues(rewriter, op, values);
    return success();
  }
};

} // namespace

void idr::bufferize::attachDataModels(MLIRContext *ctx) {
  idr::DataMatchOp::attachInterface<GivenModel<idr::DataMatchOp>>(*ctx);
  idr::LitMatchOp::attachInterface<GivenModel<idr::LitMatchOp>>(*ctx);
  idr::MemoRunOp::attachInterface<GivenModel<idr::MemoRunOp>>(*ctx);
  idr::LifetimeOp::attachInterface<GivenModel<idr::LifetimeOp>>(*ctx);
  idr::YieldOp::attachInterface<GivingModel<idr::YieldOp>>(*ctx);
  idr::ArrayOpenOp::attachInterface<OpenModel>(*ctx);
  idr::CountTakeOpenOp::attachInterface<TakeOpenModel>(*ctx);
}
