// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The boundaries: idr.func, idr.call and idr.return, shaped like upstream's
// models of func.func, func.call and func.return.
//
// A tensor parameter may be written in place by its function, and each
// caller copies where it still reads the argument afterwards: upstream's
// calling convention, which the module analysis decides per call from what
// it found of the callee. Every buffer that crosses a call is a whole cell,
// so the types at a boundary are the tensors' cell buffers, and no model
// reads a callee to learn a type. A linear tensor is no tensor here: its
// caller released it before the call, and the pass's retyping changes its
// type.
#include "idr/Transforms/BufferizeModels.h"

#include "mlir/Dialect/Bufferization/IR/Bufferization.h"
#include "mlir/Dialect/Bufferization/IR/UnstructuredControlFlow.h"
#include "mlir/Dialect/Bufferization/Transforms/Bufferize.h"
#include "mlir/Dialect/Bufferization/Transforms/FuncBufferizableOpInterfaceImpl.h"
#include "mlir/Dialect/Bufferization/Transforms/OneShotAnalysis.h"

#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/SmallVectorExtras.h"

#include <optional>

using namespace mlir;
using namespace mlir::bufferization;
namespace calls = mlir::bufferization::func_ext;

namespace {

// What the module analysis found of functions, when the analysis asking is
// the module analysis.
const calls::FuncAnalysisState *moduleFacts(const AnalysisState &state) {
  auto *oneShot = dyn_cast<OneShotAnalysisState>(&state);
  return oneShot ? oneShot->getExtension<calls::FuncAnalysisState>() : nullptr;
}

// Whether the analysis put parameter `index` of `callee` in one of its
// sets (the parameters read, or written).
template <typename Sets>
bool holds(const Sets &sets, FunctionOpInterface callee, int64_t index) {
  auto found = sets.find(callee);
  return found != sets.end() && found->second.contains(index);
}

// The results that may return parameter `index` of `callee`.
ArrayRef<int64_t> returnedAs(const calls::FuncAnalysisState &facts, FunctionOpInterface callee,
                             int64_t index) {
  auto byCallee = facts.aliasingReturnVals.find(callee);
  if (byCallee == facts.aliasingReturnVals.end())
    return {};
  auto byArg = byCallee->second.find(index);
  if (byArg == byCallee->second.end())
    return {};
  return byArg->second;
}

// The parameter that result `result` of `callee` is on every path, if one.
std::optional<int64_t> equivalentArg(const calls::FuncAnalysisState &facts,
                                     FunctionOpInterface callee, int64_t result) {
  auto byCallee = facts.equivalentFuncArgs.find(callee);
  if (byCallee == facts.equivalentFuncArgs.end())
    return std::nullopt;
  auto byResult = byCallee->second.find(result);
  if (byResult == byCallee->second.end())
    return std::nullopt;
  return byResult->second;
}

} // namespace

FunctionOpInterface idr::bufferize::analyzedCallee(idr::CallOp call, const AnalysisState &state) {
  const calls::FuncAnalysisState *facts = moduleFacts(state);
  if (!facts)
    return {};
  auto callee = dyn_cast_or_null<FunctionOpInterface>(
      cast<CallOpInterface>(call.getOperation()).resolveCallableInTable(&facts->symbolTables));
  if (!callee)
    return {};
  auto analyzed = facts->analyzedFuncOps.find(callee);
  if (analyzed == facts->analyzedFuncOps.end() ||
      analyzed->second != calls::FuncOpAnalysisState::Analyzed)
    return {};
  return callee;
}

namespace {

struct FuncModel
    : OpWithUnstructuredControlFlowBufferizableOpInterfaceExternalModel<FuncModel, idr::FuncOp> {
  using Branches =
      OpWithUnstructuredControlFlowBufferizableOpInterfaceExternalModel<FuncModel, idr::FuncOp>;

  // Contification and the inlining of a callee that ends unreachable make
  // blocks.
  static bool supportsUnstructuredControlFlow() { return true; }

  bool hasTensorSemantics(Operation *op) const {
    auto fn = cast<idr::FuncOp>(op);
    auto isTensor = llvm::IsaPred<TensorLikeType>;
    if (llvm::any_of(fn.getArgumentTypes(), isTensor) ||
        llvm::any_of(fn.getResultTypes(), isTensor))
      return true;
    for (Block &block : fn.getBody())
      if (llvm::any_of(block.getArgumentTypes(), isTensor))
        return true;
    return false;
  }

  // A parameter is a buffer of its own; another block's argument is what
  // its branches pass.
  AliasingOpOperandList getAliasingOpOperands(Operation *op, Value value,
                                              const AnalysisState &state) const {
    return getAliasingBranchOpOperands(op, cast<BlockArgument>(value), state);
  }

  FailureOr<BufferLikeType> getBufferType(Operation *op, Value value,
                                          const BufferizationOptions &options,
                                          const BufferizationState &state,
                                          SmallVector<Value> &invocationStack) const {
    auto fn = cast<idr::FuncOp>(op);
    if (cast<BlockArgument>(value).getOwner() == &fn.getBody().front())
      return idr::bufferize::cellType(value);
    return Branches::getBufferType(op, value, options, state, invocationStack);
  }

  // Every caller copies an argument it still reads after the call, so the
  // function may write each parameter in place.
  bool isWritable(Operation *, Value, const AnalysisState &) const { return true; }

  LogicalResult bufferize(Operation *op, RewriterBase &rewriter,
                          const BufferizationOptions &options, BufferizationState &state) const {
    auto fn = cast<idr::FuncOp>(op);
    FunctionType type = fn.getFunctionType();
    auto inputs = llvm::map_to_vector(type.getInputs(), idr::bufferize::boundaryType);
    auto results = llvm::map_to_vector(type.getResults(), idr::bufferize::boundaryType);

    for (Block &block : fn.getBody())
      if (failed(bufferizeBlockSignature(&block, rewriter, options, state)))
        return failure();

    for (Block &block : fn.getBody()) {
      auto ret = dyn_cast<idr::ReturnOp>(block.getTerminator());
      if (!ret)
        continue;
      rewriter.setInsertionPoint(ret);
      SmallVector<Value> values;
      for (auto [value, resultType] : llvm::zip_equal(ret->getOperands(), results)) {
        if (!isa<TensorLikeType>(value.getType())) {
          values.push_back(value);
          continue;
        }
        values.push_back(ToBufferOp::create(rewriter, ret.getLoc(), resultType, value));
      }
      rewriter.modifyOpInPlace(ret, [&] { ret->setOperands(values); });
    }

    rewriter.modifyOpInPlace(
        fn, [&] { fn.setFunctionType(FunctionType::get(op->getContext(), inputs, results)); });
    return success();
  }
};

struct CallModel : BufferizableOpInterface::ExternalModel<CallModel, idr::CallOp> {
  // A callee the module analysis has not finished reads and writes every
  // operand; so does every callee under a nested analysis, which reads no
  // sibling function.
  bool bufferizesToMemoryRead(Operation *op, OpOperand &operand, const AnalysisState &state) const {
    FunctionOpInterface callee = idr::bufferize::analyzedCallee(cast<idr::CallOp>(op), state);
    return !callee || holds(moduleFacts(state)->readBbArgs, callee, operand.getOperandNumber());
  }

  bool bufferizesToMemoryWrite(Operation *op, OpOperand &operand,
                               const AnalysisState &state) const {
    FunctionOpInterface callee = idr::bufferize::analyzedCallee(cast<idr::CallOp>(op), state);
    return !callee || holds(moduleFacts(state)->writtenBbArgs, callee, operand.getOperandNumber());
  }

  // The results a returned parameter may come back as: equivalent when the
  // callee returns exactly that parameter's buffer on every path.
  AliasingValueList getAliasingValues(Operation *op, OpOperand &operand,
                                      const AnalysisState &state) const {
    FunctionOpInterface callee = idr::bufferize::analyzedCallee(cast<idr::CallOp>(op), state);
    if (!callee)
      return bufferization::detail::unknownGetAliasingValues(operand);
    const calls::FuncAnalysisState &facts = *moduleFacts(state);
    int64_t index = operand.getOperandNumber();
    ArrayRef<int64_t> returned = returnedAs(facts, callee, index);
    bool equivalent =
        returned.size() == 1 && equivalentArg(facts, callee, returned.front()) == index;
    AliasingValueList aliases;
    for (int64_t result : returned)
      aliases.addAlias({op->getResult(static_cast<unsigned>(result)),
                        equivalent ? BufferRelation::Equivalent : BufferRelation::Unknown,
                        /*isDefinite=*/equivalent});
    return aliases;
  }

  FailureOr<BufferLikeType> getBufferType(Operation *, Value value, const BufferizationOptions &,
                                          const BufferizationState &,
                                          SmallVector<Value> &) const {
    return idr::bufferize::cellType(value);
  }

  LogicalResult bufferize(Operation *op, RewriterBase &rewriter,
                          const BufferizationOptions &options, BufferizationState &state) const {
    auto call = cast<idr::CallOp>(op);
    auto results = llvm::map_to_vector(call->getResultTypes(), idr::bufferize::boundaryType);
    SmallVector<Value> args;
    for (Value arg : call->getOperands()) {
      if (!isa<TensorLikeType>(arg.getType())) {
        args.push_back(arg);
        continue;
      }
      FailureOr<Value> buffer = idr::bufferize::cellBuffer(rewriter, arg, options, state);
      if (failed(buffer))
        return failure();
      args.push_back(*buffer);
    }
    auto bufferized = idr::CallOp::create(rewriter, call.getLoc(), results, args,
                                          call.getProperties(),
                                          call->getDiscardableAttrDictionary().getValue());
    replaceOpWithBufferizedValues(rewriter, call, bufferized->getResults());
    return success();
  }
};

// The function's model rewrites its returns with its signature.
struct ReturnModel : BufferizableOpInterface::ExternalModel<ReturnModel, idr::ReturnOp> {
  bool bufferizesToMemoryRead(Operation *, OpOperand &, const AnalysisState &) const {
    return true;
  }
  bool bufferizesToMemoryWrite(Operation *, OpOperand &, const AnalysisState &) const {
    return false;
  }
  AliasingValueList getAliasingValues(Operation *, OpOperand &, const AnalysisState &) const {
    return {};
  }
  LogicalResult bufferize(Operation *, RewriterBase &, const BufferizationOptions &,
                          BufferizationState &) const {
    return success();
  }
};

} // namespace

void idr::bufferize::attachFunctionModels(MLIRContext *ctx) {
  idr::FuncOp::attachInterface<FuncModel>(*ctx);
  idr::CallOp::attachInterface<CallModel>(*ctx);
  idr::ReturnOp::attachInterface<ReturnModel>(*ctx);
}
