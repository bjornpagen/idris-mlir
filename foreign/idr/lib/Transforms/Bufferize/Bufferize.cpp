// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-bufferize: One-Shot Bufferize on the whole program, once.
//
// Which buffer a call may write in place is a fact across calls, so the
// analysis is the program's: upstream's module driver orders the functions
// callee first, analyzes the functions of a cycle of calls together until
// their boundaries are a fixpoint, and analyzes every other function once;
// upstream's own function-boundary models read idr.func, idr.call and
// idr.return through FunctionOpInterface, CallOpInterface and ReturnLike,
// as they read func's, and the models of this directory tell it what every
// other idr op does with a tensor. The driver's steps are written out
// (empty tensor elimination, analysis, copies, rewrite) so that every
// analysis of the program is this pass's, with its options, and a failed
// one is reported here: an analysis that fails is the compiler's broken
// invariant.
//
// On the buffers, a read of an element that holds references, whose place
// the next write to the buffer overwrites, is the element's update
// (idr.element.update): the element moves out with the buffer's reference
// and the written value moves in, so a vector's pop counts nothing twice.
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

#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
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

#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/SmallVectorExtras.h"

#include <cstdint>
#include <memory>
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
// So a step of One-Shot that fails is the compiler's broken invariant,
// reported with One-Shot's own words, which the step's handler keeps.
LogicalResult underOneShot(idr::ProgramOp program, function_ref<LogicalResult()> step) {
  SmallVector<Kept> kept;
  LogicalResult result = failure();
  {
    ScopedDiagnosticHandler keep(program->getContext(), keepErrors(kept));
    result = step();
  }
  if (succeeded(result))
    return success();
  if (kept.empty())
    program.emitError("internal error: idr-bufferize: One-Shot Bufferize failed without a "
                      "diagnostic");
  for (const Kept &error : kept) {
    InFlightDiagnostic out = emitError(error.loc)
                             << "internal error: idr-bufferize: " << error.message;
    for (const auto &[loc, text] : error.notes)
      out.attachNote(loc) << text;
  }
  return failure();
}

// Whether `op`, or an op in it, takes a buffer, at any grade. A call's
// effects say nothing of the buffers it is given, which its callee may write,
// and a view or a grade change of a buffer is that buffer again, so no op
// that takes one lies between a read of an element and the write of it.
bool takesBuffer(Operation *op) {
  return op
      ->walk([](Operation *inner) {
        return llvm::any_of(inner->getOperandTypes(),
                            [](Type type) { return isa<BaseMemRefType>(idr::unrestricted(type)); })
                   ? WalkResult::interrupt()
                   : WalkResult::advance();
      })
      .wasInterrupted();
}

// The read of the element `store` overwrites: the load of the same element
// that is the nearest op before the store, in its block, that takes a buffer
// or does more than compute, when no op between uses what it read. What lies
// between is judged by itself alone, never by what a callee is known to do,
// so the rule holds whatever bufferization made of the calls. The ops before
// the store in its block are finitely many.
std::optional<memref::LoadOp> readBefore(memref::StoreOp store) {
  for (Operation *op = store->getPrevNode(); op; op = op->getPrevNode()) {
    if (!takesBuffer(op) && idr::onlyAllocates(op, nullptr))
      continue;
    auto load = dyn_cast<memref::LoadOp>(op);
    if (!load || !idr::sameElement(load.getMemref(), load.getIndices(), store.getMemref(),
                                   store.getIndices()))
      return std::nullopt;
    Block *block = store->getBlock();
    bool usedBetween = llvm::any_of(load.getResult().getUses(), [&](OpOperand &use) {
      Operation *ancestor = block->findAncestorOpInBlock(*use.getOwner());
      return ancestor && ancestor->isBeforeInBlock(store);
    });
    if (usedBetween)
      return std::nullopt;
    return load;
  }
  return std::nullopt;
}

// Each write of an element that holds references into a value array's
// buffer, read just before it, becomes the element's update, where the
// write was: the element leaves the op when anything after the write uses
// it, and the written value, the element itself when the write gives it
// back, is the first value the region yields.
void moveElementsOut(idr::ProgramOp program) {
  SmallVector<memref::StoreOp> stores;
  program.walk([&](memref::StoreOp store) {
    MemRefType buffer = store.getMemRefType();
    if (!buffer.getMemorySpace() && idr::holdsReferences(buffer.getElementType()))
      stores.push_back(store);
  });
  IRRewriter rewriter(program->getContext());
  for (memref::StoreOp store : stores) {
    std::optional<memref::LoadOp> load = readBefore(store);
    if (!load)
      continue;
    Value element = load->getResult();
    bool leaves = llvm::any_of(element.getUsers(),
                               [&](Operation *user) { return user != store.getOperation(); });
    SmallVector<Type> outs;
    if (leaves)
      outs.push_back(element.getType());
    Location loc = rewriter.getFusedLoc({load->getLoc(), store.getLoc()});
    rewriter.setInsertionPoint(store);
    // An update takes its indices as words, as an array a world orders does.
    SmallVector<Value> indices = llvm::map_to_vector(store.getIndices(), [&](Value index) -> Value {
      return arith::IndexCastOp::create(rewriter, loc, rewriter.getI64Type(), index);
    });
    auto update = idr::ElementUpdateOp::create(rewriter, loc, outs, store.getMemref(), indices);
    rewriter.createBlock(&update.getRegion(), {}, {element.getType()}, {load->getLoc()});
    Value moving = update.getElement();
    SmallVector<Value> yielded{store.getValueToStore() == element ? moving
                                                                  : store.getValueToStore()};
    if (leaves)
      yielded.push_back(moving);
    idr::ArrayYieldOp::create(rewriter, loc, yielded);
    rewriter.eraseOp(store);
    if (leaves)
      rewriter.replaceAllUsesWith(element, update.getOuts().front());
    rewriter.eraseOp(*load);
  }
}

struct Bufferize : idr::impl::IdrBufferizeBase<Bufferize> {
  // The models are attached wherever the pass runs, with the dialects it
  // creates ops of; the pass manager appends every pass's registry before
  // the pipeline runs, so a pass before this one that analyzes for
  // bufferization sees them too.
  // The indices of an element's update are words, cast from the store's.
  void getDependentDialects(DialectRegistry &registry) const override {
    Base::getDependentDialects(registry);
    registry.insert<arith::ArithDialect>();
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

    // A tensor.empty whose array is inserted into a slice of another becomes
    // that slice, decided on an analysis of its own, since the elimination
    // changes the program the analysis below must see.
    {
      OneShotAnalysisState elimination(program, options);
      if (failed(underOneShot(program, [&] {
            IRRewriter rewriter(ctx);
            return success(succeeded(analyzeModuleOp(program, elimination)) &&
                           succeeded(eliminateEmptyTensors(rewriter, program, elimination)));
          })))
        return signalPassFailure();
    }

    OneShotAnalysisState analysis(program, options);
    BufferizationStatistics statistics;
    BufferizationState rewrite;
    if (failed(underOneShot(program,
                            [&] { return analyzeModuleOp(program, analysis, &statistics); })) ||
        failed(underOneShot(program, [&] {
          return success(succeeded(insertTensorCopies(program, analysis, rewrite)) &&
                         succeeded(bufferizeModuleOp(program, options, rewrite, &statistics)));
        })))
      return signalPassFailure();
    moveElementsOut(program);

    // Every tensor left in a function is inside another type: a wrapper, a
    // body, a signature. Each becomes its cell's buffer, and a data type
    // whose body held one becomes a new type of its own. The values are the
    // functions'; the initial value of a constant's global, beside them in
    // the program, is a constant of tensor type, whatever buffer holds it.
    auto toBuffer = [](Type type,
                       std::optional<idr::DataRemap::FieldPlace>) -> std::optional<Type> {
      if (auto tensor = dyn_cast<RankedTensorType>(type))
        return idr::bufferize::bufferType(tensor);
      return std::nullopt;
    };
    FailureOr<std::unique_ptr<idr::DataRemap>> buffers =
        idr::DataRemap::create(program, "buffers", toBuffer);
    if (failed(buffers))
      return signalPassFailure();
    for (idr::FuncOp fn : program.getOps<idr::FuncOp>())
      (*buffers)->retype(fn);

    numAllocs += static_cast<uint64_t>(statistics.numBufferAlloc);
    numInPlace += static_cast<uint64_t>(statistics.numTensorInPlace);
    numCopies += static_cast<uint64_t>(statistics.numTensorOutOfPlace);
  }
};

} // namespace
