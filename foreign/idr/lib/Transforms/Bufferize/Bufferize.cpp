// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-bufferize: One-Shot Bufferize on the whole program, once.
//
// Which buffer a call may write in place is a fact across calls, so the
// analysis is the module's: upstream's module driver orders the functions
// callee first and analyzes each, and the models of this directory tell it
// what each idr op does with a tensor. The driver's steps are written out
// (analysis, copies, rewrite) so that what the analysis found is read
// between them: a copy forced at a call on a cycle of calls is a remark,
// and a failed analysis is reported at the op it concerns.
//
// A buffer is a cell of the runtime: an allocation is memref.alloc, which
// idr-lower makes the runtime's cell, and a copy is memref.copy, the
// runtime's copy, which counts the references of the elements it copies.
// No ownership deallocation runs: counting frees cells, one ownership
// system and not two.
//
// A linear array is no tensor to One-Shot, and nor is a data type that
// holds one: the wrapper and the body are ours. Once every tensor has its
// buffer, one retyping of the module turns every tensor left inside another
// type into its cell's buffer type, so a wrapper keeps its grade around the
// buffer and a body holds the buffer.
#include "idr/Transforms/Bufferize.h"

#include "idr/Transforms/BufferizeModels.h"

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"

#include "mlir/Dialect/Bufferization/IR/Bufferization.h"
#include "mlir/Dialect/Bufferization/IR/BufferizationTypeInterfaces.h"
#include "mlir/Dialect/Bufferization/Transforms/Bufferize.h"
#include "mlir/Dialect/Bufferization/Transforms/OneShotAnalysis.h"
#include "mlir/Dialect/Bufferization/Transforms/OneShotModuleBufferize.h"
#include "mlir/Dialect/Bufferization/Transforms/Transforms.h"
#include "mlir/Dialect/Linalg/IR/Linalg.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/Dominance.h"
#include "mlir/IR/Remarks.h"

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

MemRefType idr::bufferize::bufferType(RankedTensorType type) {
  return cast<MemRefType>(getMemRefTypeWithStaticIdentityLayout(type));
}

BufferLikeType idr::bufferize::cellType(Value value) {
  return cast<BufferLikeType>(bufferType(cast<RankedTensorType>(value.getType())));
}

Type idr::bufferize::boundaryType(Type type) {
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
    attachFunctionModels(ctx);
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

// No program reaches a failure of One-Shot: a linear array aliases nothing
// by the library's construction, and every op that holds a tensor has a
// model. So each is the compiler's broken invariant.
void reportInternal(ModuleOp module, ArrayRef<Kept> kept) {
  if (kept.empty()) {
    module.emitError("internal error: idr-bufferize: One-Shot Bufferize failed without a "
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

// A link must bufferize in place, so a read of its buffer after the
// release fails One-Shot's check before any decision. The error names the
// link and each read its release comes before on every path, with
// One-Shot's own message; where no link has such a read, One-Shot's errors
// are what there is to say.
void reportAnalysisFailure(ModuleOp module, const OneShotAnalysisState &state,
                           ArrayRef<Kept> kept) {
  std::string why = kept.empty() ? "One-Shot's analysis failed" : kept.front().message;
  bool named = false;
  for (idr::FuncOp fn : module.getOps<idr::FuncOp>()) {
    DominanceInfo dominance(fn);
    fn.walk([&](idr::LinEnterOp enter) {
      OpOperand &released = enter->getOpOperand(0);
      if (!isa<TensorLikeType>(released.get().getType()) || !idr::bufferize::isLink(enter, state))
        return;
      SmallVector<Operation *> reads;
      for (OpOperand &use : released.get().getUses())
        if (use.getOwner() != enter.getOperation() &&
            dominance.properlyDominates(enter.getOperation(), use.getOwner()) &&
            state.bufferizesToMemoryRead(use))
          reads.push_back(use.getOwner());
      if (reads.empty())
        return;
      InFlightDiagnostic error =
          enter.emitError() << "internal error: idr-bufferize: the linear array released here "
                               "is read after its release: "
                            << why;
      for (Operation *read : reads)
        error.attachNote(read->getLoc()) << "read here";
      named = true;
    });
  }
  if (!named)
    reportInternal(module, kept);
}

// Upstream's module analysis does not summarize a function on a cycle of
// calls, and assumes that a call of one reads and writes every operand.
// Each copy that assumption makes is a remark, for the program whose hot
// path would want the analysis to reach a cycle's fixpoint.
void remarkCopiesAtCycles(ModuleOp module, const OneShotAnalysisState &state) {
  if (!module->getContext()->getRemarkEngine())
    return;
  module.walk([&](idr::CallOp call) {
    if (idr::bufferize::analyzedCallee(call, state))
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
    ModuleOp module = getOperation();
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

    OneShotAnalysisState analysis(module, options);
    BufferizationStatistics statistics;
    SmallVector<Kept> kept;
    bool analyzed;
    {
      ScopedDiagnosticHandler keep(ctx, keepErrors(kept));
      analyzed = succeeded(analyzeModuleOp(module, analysis, &statistics));
    }
    if (!analyzed) {
      reportAnalysisFailure(module, analysis, kept);
      return signalPassFailure();
    }
    remarkCopiesAtCycles(module, analysis);

    BufferizationState rewrite;
    bool rewritten;
    {
      ScopedDiagnosticHandler keep(ctx, keepErrors(kept));
      rewritten = succeeded(insertTensorCopies(module, analysis, rewrite)) &&
                  succeeded(bufferizeModuleOp(module, options, rewrite, &statistics));
    }
    if (!rewritten) {
      reportInternal(module, kept);
      return signalPassFailure();
    }

    // Every tensor left is inside another type: a wrapper, a body, a
    // signature. Each becomes its cell's buffer, and a data type whose body
    // held one becomes a new type of its own.
    auto toBuffer = [](Type type, idr::DataType, unsigned, unsigned) -> std::optional<Type> {
      if (auto tensor = dyn_cast<RankedTensorType>(type))
        return idr::bufferize::bufferType(tensor);
      return std::nullopt;
    };
    idr::DataRemap buffers(module, "buffers", toBuffer);
    buffers.retype(module);

    numAllocs += static_cast<uint64_t>(statistics.numBufferAlloc);
    numInPlace += static_cast<uint64_t>(statistics.numTensorInPlace);
    numCopies += static_cast<uint64_t>(statistics.numTensorOutOfPlace);
  }
};

} // namespace
