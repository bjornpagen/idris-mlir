// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-bufferize: One-Shot Bufferize on the whole program, once.
//
// Which buffer a call may write in place is a fact across calls, so the
// analysis is the program's: upstream's module driver orders the functions
// callee first and analyzes each, upstream's own function-boundary models
// read idr.func, idr.call and idr.return through FunctionOpInterface,
// CallOpInterface and ReturnLike, as they read func's, and the models of
// this directory tell it what every other idr op does with a tensor. The
// driver's steps are written out (empty tensor elimination, analysis,
// copies, rewrite) so that every analysis of the program is this pass's,
// with its options, and a failed one is reported here: a copy forced at a
// call on a cycle of calls is a remark, and an analysis that fails is the
// compiler's broken invariant.
//
// A buffer is a cell of the runtime: an allocation is memref.alloc, which
// idr-lower makes the runtime's cell, and a copy is memref.copy, the
// runtime's copy, which counts the references of the elements it copies.
// No ownership deallocation runs: counting frees cells, one ownership
// system and not two.
//
// A linear array is no tensor to One-Shot, and nor is a data type that
// holds one: a type interface belongs to its class, and the class of a
// linear array is that of every grade, the world's included. Once every
// tensor has its buffer, one retyping of the program turns every tensor
// left inside another type into its cell's buffer type, so a wrapper keeps
// its grade around the buffer and a body holds the buffer.
#include "idr/Transforms/Bufferize.h"

#include "idr/Transforms/BufferizeModels.h"

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"

#include "mlir/Dialect/Bufferization/IR/Bufferization.h"
#include "mlir/Dialect/Bufferization/IR/BufferizationTypeInterfaces.h"
#include "mlir/Dialect/Bufferization/Transforms/Bufferize.h"
#include "mlir/Dialect/Bufferization/Transforms/FuncBufferizableOpInterfaceImpl.h"
#include "mlir/Dialect/Bufferization/Transforms/OneShotAnalysis.h"
#include "mlir/Dialect/Bufferization/Transforms/OneShotModuleBufferize.h"
#include "mlir/Dialect/Bufferization/Transforms/Transforms.h"
#include "mlir/Dialect/Linalg/IR/Linalg.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/Remarks.h"
#include "mlir/Interfaces/CallInterfaces.h"

#include "llvm/ADT/SmallVector.h"

#include <cstdint>
#include <optional>
#include <string>
#include <utility>

namespace idr {
#define GEN_PASS_DEF_IDRBUFFERIZE
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;
using namespace mlir::bufferization;
namespace calls = mlir::bufferization::func_ext;

MemRefType idr::bufferize::bufferType(RankedTensorType type) {
  return cast<MemRefType>(getMemRefTypeWithStaticIdentityLayout(type));
}

BufferLikeType idr::bufferize::cellType(Value value) {
  return cast<BufferLikeType>(bufferType(cast<RankedTensorType>(value.getType())));
}

Type idr::bufferize::heldType(Type type) {
  if (auto tensor = dyn_cast<RankedTensorType>(type))
    return bufferType(tensor);
  return type;
}

FailureOr<Value> idr::bufferize::cellBuffer(RewriterBase &rewriter, Value value,
                                            const BufferizationOptions &options,
                                            const BufferizationState &state) {
  FailureOr<Value> buffer = getBuffer(rewriter, value, options, state);
  if (failed(buffer))
    return failure();
  MemRefType cell = bufferType(cast<RankedTensorType>(value.getType()));
  if (buffer->getType() == cell)
    return buffer;
  return castOrReallocMemRefValue(rewriter, *buffer, cell, options);
}

void idr::bufferize::registerModels(DialectRegistry &registry) {
  registry.addExtension(+[](MLIRContext *ctx, idr::IdrDialect *) {
    idr::FuncOp::attachInterface<calls::FuncOpBufferizableModel<idr::FuncOp>>(*ctx);
    idr::CallOp::attachInterface<calls::CallOpBufferizableModel<idr::CallOp>>(*ctx);
    idr::ReturnOp::attachInterface<calls::ReturnOpBufferizableModel<idr::ReturnOp>>(*ctx);
    attachLinearModels(ctx);
    attachDataModels(ctx);
    attachTieShapeModel(ctx);
  });
  registry.addExtension(+[](MLIRContext *ctx, ub::UBDialect *) { attachPoisonModel(ctx); });
}

bool idr::bufferize::copies(Operation *op) {
  auto copy = dyn_cast<memref::CopyOp>(op);
  return copy && copy.getTarget().getDefiningOp<memref::AllocOp>();
}

namespace {

// An error One-Shot reported, kept until the pass knows what to say: an
// error of the analysis concerns the program's invariants, which only the
// pass can name.
struct Kept {
  Location loc;
  std::string message;
  SmallVector<std::pair<Location, std::string>> notes;
};

// A handler that keeps every error and lets every other diagnostic through.
auto keepErrors(SmallVectorImpl<Kept> &kept) {
  return [&kept](Diagnostic &diagnostic) -> LogicalResult {
    if (diagnostic.getSeverity() != DiagnosticSeverity::Error)
      return failure();
    Kept error{diagnostic.getLocation(), diagnostic.str(), {}};
    for (Diagnostic &note : diagnostic.getNotes())
      error.notes.emplace_back(note.getLocation(), note.str());
    kept.push_back(std::move(error));
    return success();
  };
}

// No program reaches a failure of One-Shot: a link is an entry nothing
// touches after, a release whose buffer a later write would overwrite was
// given a buffer of its own, and every op that holds a tensor has a model.
// So each is the compiler's broken invariant, reported with One-Shot's own
// words.
void reportInternal(idr::ProgramOp program, ArrayRef<Kept> kept) {
  if (kept.empty()) {
    program.emitError("internal error: idr-bufferize: One-Shot Bufferize failed without a "
                      "diagnostic");
    return;
  }
  for (const Kept &error : kept) {
    InFlightDiagnostic out = emitError(error.loc)
                             << "internal error: idr-bufferize: " << error.message;
    for (const auto &[loc, text] : error.notes)
      out.attachNote(loc) << text;
  }
}

// Upstream's module analysis does not summarize a function on a cycle of
// calls, and assumes that a call of one reads and writes every operand.
// Each copy that assumption makes is a remark, for the program whose hot
// path would want the analysis to reach a cycle's fixpoint.
void remarkCopiesAtCycles(idr::ProgramOp program, const OneShotAnalysisState &state) {
  if (!program->getContext()->getRemarkEngine())
    return;
  program.walk([&](idr::CallOp call) {
    FunctionOpInterface callee =
        calls::getCalledFunction(cast<CallOpInterface>(call.getOperation()), state);
    if (callee &&
        calls::getFuncOpAnalysisState(state, callee) == calls::FuncOpAnalysisState::Analyzed)
      return;
    for (OpOperand &arg : call->getOpOperands())
      if (isa<TensorLikeType>(arg.get().getType()) && !state.isInPlace(arg))
        remark::missed(call.getLoc(), remark::RemarkOpts::name("Copy").category("idr-bufferize"))
            << StringRef("the array is copied before this call: the callee is on a cycle of "
                         "calls, whose analysis assumes it reads and writes every array it is "
                         "given");
  });
}

struct Bufferize : idr::impl::IdrBufferizeBase<Bufferize> {
  // The models are attached wherever the pass runs, with the dialects it
  // creates ops of; the pass manager appends every pass's registry before
  // the pipeline runs, so a pass before this one that analyzes for
  // bufferization sees them too.
  void getDependentDialects(DialectRegistry &registry) const override {
    Base::getDependentDialects(registry);
    idr::bufferize::registerModels(registry);
  }

  void runOnOperation() override {
    idr::ProgramOp program = getOperation();
    MLIRContext *ctx = &getContext();

    OneShotBufferizationOptions options;
    options.bufferizeFunctionBoundaries = true;
    // A buffer that crosses a call is a whole cell, and so is a new one;
    // the defaults would give both a fully dynamic layout.
    options.setFunctionBoundaryTypeConversion(LayoutMapOption::IdentityLayoutMap);
    options.unknownTypeConverterFn = [](TensorLikeType type, Attribute memorySpace,
                                        const BufferizationOptions &) {
      return cast<BufferLikeType>(
          getMemRefTypeWithStaticIdentityLayout(cast<TensorType>(type), memorySpace));
    };
    // The cell's header places the elements, so an allocation asks for no
    // alignment of its own.
    options.bufferAlignment = 0;
    // A loop that yields a new buffer is the program's; counting frees the
    // one it replaced.
    options.allowReturnAllocsFromLoops = true;

    idr::bufferize::prepare(program, options);

    SmallVector<Kept> kept;
    // A tensor.empty whose array is inserted into a slice of another becomes
    // that slice, decided on an analysis of its own, since the elimination
    // changes the program the analysis below must see.
    {
      OneShotAnalysisState elimination(program, options);
      bool eliminated;
      {
        ScopedDiagnosticHandler keep(ctx, keepErrors(kept));
        IRRewriter rewriter(ctx);
        eliminated = succeeded(analyzeModuleOp(program, elimination)) &&
                     succeeded(eliminateEmptyTensors(rewriter, program, elimination));
      }
      if (!eliminated) {
        reportInternal(program, kept);
        return signalPassFailure();
      }
    }

    OneShotAnalysisState analysis(program, options);
    BufferizationStatistics statistics;
    bool analyzed;
    {
      ScopedDiagnosticHandler keep(ctx, keepErrors(kept));
      analyzed = succeeded(analyzeModuleOp(program, analysis, &statistics));
    }
    if (!analyzed) {
      reportInternal(program, kept);
      return signalPassFailure();
    }
    remarkCopiesAtCycles(program, analysis);

    BufferizationState rewrite;
    bool rewritten;
    {
      ScopedDiagnosticHandler keep(ctx, keepErrors(kept));
      rewritten = succeeded(insertTensorCopies(program, analysis, rewrite)) &&
                  succeeded(bufferizeModuleOp(program, options, rewrite, &statistics));
    }
    if (!rewritten) {
      reportInternal(program, kept);
      return signalPassFailure();
    }

    // Every tensor left in a function is inside another type: a wrapper, a
    // body, a signature. Each becomes its cell's buffer, and a data type
    // whose body held one becomes a new type of its own. The values are the
    // functions'; the initial value of a constant's global, beside them in
    // the program, is a constant of tensor type, whatever buffer holds it.
    auto toBuffer = [](Type type, idr::DataType, unsigned, unsigned) -> std::optional<Type> {
      if (auto tensor = dyn_cast<RankedTensorType>(type))
        return idr::bufferize::bufferType(tensor);
      return std::nullopt;
    };
    idr::DataRemap buffers(program, "buffers", toBuffer);
    for (idr::FuncOp fn : program.getOps<idr::FuncOp>())
      buffers.retype(fn);
    if (failed(buffers.status()))
      return signalPassFailure();

    numAllocs += static_cast<uint64_t>(statistics.numBufferAlloc);
    numInPlace += static_cast<uint64_t>(statistics.numTensorInPlace);
    numCopies += static_cast<uint64_t>(statistics.numTensorOutOfPlace);
  }
};

} // namespace
