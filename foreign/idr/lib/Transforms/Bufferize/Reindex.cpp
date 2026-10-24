// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr.data.reindex of an array: the array at an element type its enclosing
// refinements make equal to its own, as where an array of positions below
// 5 is taken for one of positions below a bound no index fixes. Its types
// say what it does at run time to give the array on, its carry, and the
// model answers every question by the one case the carry is. A reindex
// that changes no word is its operand's buffer, the same words at the
// result's element type, as upstream's tensor.cast is its source's. One
// that re-packs reads every element of its operand into a fresh array,
// which the lowering allocates and fills element by element: the operand
// is only read, and the result is a new buffer.
#include "idr/Transforms/BufferizeModels.h"

#include "idr/IR/Families/Families.h"
#include "idr/IR/Grades.h"

#include "mlir/Dialect/Bufferization/IR/Bufferization.h"

#include "llvm/Support/ErrorHandling.h"

#include <cassert>
#include <concepts>
#include <optional>
#include <type_traits>

using namespace mlir;
using namespace mlir::bufferization;

namespace {

using idr::DataReindexOp;

// A reindex whose element lays out as its operand's does: the operand's
// buffer itself at the result's element type, its layout and memory space
// kept, at the result's grade, which a reindex that builds nothing shares
// with its operand. It reads and writes nothing.
struct SameWords {
  DataReindexOp op;

  static constexpr bool reads = false;
  static constexpr bool allocates = false;

  AliasingValueList aliases() {
    return {{op.getResult(), BufferRelation::Equivalent, /*isDefinite=*/true}};
  }

  // The operand's buffer type `from`, as the result's.
  BufferLikeType asResult(BufferLikeType from) {
    auto buffer = cast<MemRefType>(idr::unrestricted(from));
    auto result = cast<RankedTensorType>(idr::unrestricted(op.getType()));
    auto words = MemRefType::get(result.getShape(), result.getElementType(), buffer.getLayout(),
                                 buffer.getMemorySpace());
    return cast<BufferLikeType>(idr::graded(idr::gradeOf(op.getType()), words));
  }

  FailureOr<BufferLikeType> bufferType(const BufferizationOptions &options,
                                       const BufferizationState &state,
                                       SmallVector<Value> &invocationStack) {
    FailureOr<BufferLikeType> from =
        bufferization::getBufferType(op.getValue(), options, state, invocationStack);
    if (failed(from))
      return failure();
    return asResult(*from);
  }

  // The result's type is read off the buffer the operand has, so the two
  // are laid out alike, as the reindex relates them.
  LogicalResult bufferize(RewriterBase &rewriter, const BufferizationOptions &options,
                          BufferizationState &state) {
    FailureOr<Value> buffer = getBuffer(rewriter, op.getValue(), options, state);
    if (failed(buffer))
      return failure();
    replaceOpWithNewBufferizedOp<DataReindexOp>(
        rewriter, op, asResult(cast<BufferLikeType>(buffer->getType())), *buffer, op.getOuters());
    return success();
  }
};

// A reindex whose element lays out apart: every element of its operand
// read, re-packed and placed in a fresh array, so the operand is read and
// nothing else, and the result is a new buffer whose every slot the
// re-pack writes. The two are one array at two element types, laid out
// alike but for their elements, and the fresh one is a whole cell, so the
// operand is read as its whole cell, a slice copied into one first.
struct Repacked {
  DataReindexOp op;

  static constexpr bool reads = true;
  static constexpr bool allocates = true;

  AliasingValueList aliases() { return {}; }

  FailureOr<BufferLikeType> bufferType(const BufferizationOptions &, const BufferizationState &,
                                       SmallVector<Value> &) {
    return idr::bufferize::cellType(cast<TensorLikeType>(op.getType()));
  }

  // The re-pack gives a fresh array, at the hold every building reindex
  // gives; the claim the result's tensor does not state is forgotten after
  // it. A reindex of tensors builds nothing, so it kept its operand's hold
  // and the cell claims what the operand did, which the re-pack keeps: each
  // element it places gains the reference the operand, given up, loses.
  LogicalResult bufferize(RewriterBase &rewriter, const BufferizationOptions &options,
                          BufferizationState &state) {
    FailureOr<Value> buffer = idr::bufferize::cellBuffer(rewriter, op.getValue(), options, state);
    if (failed(buffer))
      return failure();
    Type cell = idr::bufferize::cellType(cast<TensorLikeType>(op.getType()));
    std::optional<idr::Hold> stated = idr::holdOf(cell);
    assert(stated && "an array's buffer holds its cell's reference");
    Type fresh =
        idr::atHold(cell, idr::families::builtHold(idr::usesOf(cell), stated->claim()));
    Location loc = op.getLoc();
    Value made = DataReindexOp::create(rewriter, loc, fresh, *buffer).getResult();
    if (fresh != cell)
      made = idr::CountShareOp::create(rewriter, loc, cell, made).getResult();
    replaceOpWithBufferizedValues(rewriter, op, made);
    return success();
  }
};

// A question both cases answer, with one type of answer.
template <typename F>
concept AskedOfEither =
    std::invocable<F &, SameWords> && std::invocable<F &, Repacked> &&
    std::same_as<std::invoke_result_t<F &, SameWords>, std::invoke_result_t<F &, Repacked>>;

// `ask` of the case `op` is, by its carry.
template <AskedOfEither F>
std::invoke_result_t<F &, SameWords> byCarry(DataReindexOp op, F &&ask) {
  switch (op.getCarry()) {
  case idr::Carry::Free:
    return ask(SameWords{op});
  case idr::Carry::Works:
    return ask(Repacked{op});
  }
  llvm_unreachable("a reindex gives its operand on free or after work");
}

struct ReindexModel : BufferizableOpInterface::ExternalModel<ReindexModel, DataReindexOp> {
  bool bufferizesToMemoryRead(Operation *op, OpOperand &, const AnalysisState &) const {
    return byCarry(cast<DataReindexOp>(op), [](auto as) { return as.reads; });
  }
  // Neither case writes its operand: one gives it on, the other only reads
  // it.
  bool bufferizesToMemoryWrite(Operation *, OpOperand &, const AnalysisState &) const {
    return false;
  }
  AliasingValueList getAliasingValues(Operation *op, OpOperand &, const AnalysisState &) const {
    return byCarry(cast<DataReindexOp>(op), [](auto as) { return as.aliases(); });
  }
  bool bufferizesToAllocation(Operation *op, Value) const {
    return byCarry(cast<DataReindexOp>(op), [](auto as) { return as.allocates; });
  }

  FailureOr<BufferLikeType> getBufferType(Operation *op, Value, const BufferizationOptions &options,
                                          const BufferizationState &state,
                                          SmallVector<Value> &invocationStack) const {
    return byCarry(cast<DataReindexOp>(op), [&](auto as) {
      return as.bufferType(options, state, invocationStack);
    });
  }

  LogicalResult bufferize(Operation *op, RewriterBase &rewriter,
                          const BufferizationOptions &options, BufferizationState &state) const {
    return byCarry(cast<DataReindexOp>(op),
                   [&](auto as) { return as.bufferize(rewriter, options, state); });
  }
};

} // namespace

void idr::bufferize::attachReindexModel(MLIRContext *ctx) {
  idr::DataReindexOp::attachInterface<ReindexModel>(*ctx);
}
