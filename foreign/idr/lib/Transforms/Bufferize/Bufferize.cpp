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
// A graded tensor is tensor-like where its value is a tensor, by its own
// models, and its buffer keeps its grade: One-Shot bufferizes a linear
// array's wrapper and every signature that carries one itself, and a copy
// of one is an alloc_tensor of its value with the grade put back. A field
// of a cell holds its buffer from the frontend on, which crosses into the
// tensor world through upstream's to_buffer and to_tensor, so no type of
// the program is retyped after the analysis.
//
// On the buffers, a read of an element that holds references, whose place
// the next write to the buffer overwrites, is the element's update
// (idr.array.update): the element moves out with the buffer's reference
// and the written value moves in, so a vector's pop counts nothing twice.
//
// A buffer is a cell of the runtime: an allocation is memref.alloc, which
// idr-lower makes the runtime's cell, and a copy is memref.copy, the
// runtime's copy, which counts the references of the elements it copies.
// No ownership deallocation runs: counting frees cells, one ownership
// system and not two.
#include "idr/Transforms/Bufferize.h"

#include "idr/Transforms/BufferizeModels.h"

#include "idr/IR/Arrays.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Pipeline.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Bufferization/IR/Bufferization.h"
#include "mlir/Dialect/Bufferization/IR/BufferizationTypeInterfaces.h"
#include "mlir/Dialect/Bufferization/Transforms/Bufferize.h"
#include "mlir/Dialect/Bufferization/Transforms/FuncBufferizableOpInterfaceImpl.h"
#include "mlir/Dialect/Bufferization/Transforms/OneShotAnalysis.h"
#include "mlir/Dialect/Bufferization/Transforms/OneShotModuleBufferize.h"
#include "mlir/Dialect/Bufferization/Transforms/Transforms.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/Tensor/IR/Tensor.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/Matchers.h"
#include "mlir/IR/PatternMatch.h"

#include "llvm/ADT/SmallVector.h"

#include <cstdint>
#include <optional>
#include <string>
#include <type_traits>
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

BufferLikeType idr::bufferize::cellType(TensorLikeType type) {
  auto tensor = cast<RankedTensorType>(idr::unrestricted(type));
  Type buffer = bufferType(tensor);
  if (type != tensor)
    buffer = idr::graded(idr::gradeOf(type), buffer);
  return cast<BufferLikeType>(buffer);
}

FailureOr<Value> idr::bufferize::cellBuffer(RewriterBase &rewriter, Value value,
                                            const BufferizationOptions &options,
                                            const BufferizationState &state) {
  FailureOr<Value> buffer = getBuffer(rewriter, value, options, state);
  if (failed(buffer))
    return failure();
  BufferLikeType cell = cellType(cast<TensorLikeType>(value.getType()));
  if (buffer->getType() == cell)
    return buffer;
  // A graded buffer is a whole cell wherever it is made, so only a plain
  // one is ever a slice.
  return castOrReallocMemRefValue(rewriter, *buffer, cast<MemRefType>(cell), options);
}

void idr::bufferize::registerModels(DialectRegistry &registry) {
  registry.addExtension(+[](MLIRContext *ctx, idr::IdrDialect *) {
    idr::FuncOp::attachInterface<calls::FuncOpBufferizableModel<idr::FuncOp>>(*ctx);
    idr::CallOp::attachInterface<calls::CallOpBufferizableModel<idr::CallOp>>(*ctx);
    idr::ReturnOp::attachInterface<calls::ReturnOpBufferizableModel<idr::ReturnOp>>(*ctx);
    attachGradedModels(ctx);
    attachLinearModels(ctx);
    attachDataModels(ctx);
    attachGeneratingModels(ctx);
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

// No program reaches a failure of One-Shot: a write of an exclusive
// array's thread is in place by its grade, a release whose buffer a later
// write would overwrite was given a buffer of its own, and every op that
// holds a tensor has a model. So a step of One-Shot that fails is the
// compiler's broken invariant, reported with One-Shot's own words, which
// the step's handler keeps.
template <typename Step>
  requires std::is_invocable_r_v<LogicalResult, Step>
LogicalResult underOneShot(idr::ProgramOp program, Step &&step) {
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

// Whether two indices are one: the same value, or two constants of the same
// value, which a pass that puts a constant in place of a value it knows
// makes once per use.
bool sameIndex(Value x, Value y) {
  if (x == y)
    return true;
  APInt a, b;
  return matchPattern(x, m_ConstantInt(&a)) && matchPattern(y, m_ConstantInt(&b)) &&
         a.getBitWidth() == b.getBitWidth() && a == b;
}

// The read of the element `store` overwrites: the load of the same element
// of the same buffer that is the nearest op before the store, in its block,
// that takes a buffer or does more than compute and crash (a read moves
// across a crash, which nothing after observes), when no op between uses
// what it read. What lies between is judged by itself alone, never by what
// a callee is known to do, so the rule holds whatever bufferization made of
// the calls. The ops before the store in its block are finitely many.
std::optional<memref::LoadOp> readBefore(memref::StoreOp store) {
  for (Operation *op = store->getPrevNode(); op; op = op->getPrevNode()) {
    if (!takesBuffer(op) && idr::arrays::computesOnly(op))
      continue;
    auto load = dyn_cast<memref::LoadOp>(op);
    if (!load || load.getMemref() != store.getMemref() ||
        !llvm::equal(load.getIndices(), store.getIndices(), sameIndex))
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
// back, is the first value the region gives.
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
    auto update = idr::ArrayUpdateOp::create(rewriter, loc, outs, store.getMemref(),
                                             store.getIndices());
    rewriter.createBlock(&update.getRegion(), {}, {element.getType()}, {load->getLoc()});
    Value moving = update.getRegion().front().getArgument(0);
    Value back = store.getValueToStore() == element ? moving : store.getValueToStore();
    SmallVector<Value> out;
    if (leaves)
      out.push_back(moving);
    idr::ArrayUpdateYieldOp::create(rewriter, loc, back, out);
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
  void getDependentDialects(DialectRegistry &registry) const override {
    Base::getDependentDialects(registry);
    idr::bufferize::registerModels(registry);
  }

  void runOnProgram(idr::ProgramOp program) override {
    MLIRContext *ctx = &getContext();

    OneShotBufferizationOptions options;
    options.bufferizeFunctionBoundaries = true;
    // A buffer that crosses a call is a whole cell, and so is a new one;
    // the defaults would give both a fully dynamic layout.
    options.setFunctionBoundaryTypeConversion(LayoutMapOption::IdentityLayoutMap);
    // A tensor-like type that is not a builtin tensor is a graded one: its
    // buffer is its cell's at its grade.
    options.unknownTypeConverterFn = [](TensorLikeType type, Attribute,
                                        const BufferizationOptions &) {
      return idr::bufferize::cellType(type);
    };
    // A graded tensor's copy is a copy of its value at its grade; one with
    // undefined contents, a new value of its shape at its grade.
    options.tensorAllocationFn = [](OpBuilder &b, Location loc, Value value, bool copy,
                                    const BufferizationOptions &) -> FailureOr<Value> {
      auto tensor = cast<RankedTensorType>(idr::unrestricted(value.getType()));
      Value plain = idr::heldAs(b, loc, value, tensor);
      SmallVector<Value> sizes;
      if (!copy)
        for (int64_t d = 0, e = tensor.getRank(); d < e; ++d)
          if (tensor.isDynamicDim(d))
            sizes.push_back(tensor::DimOp::create(b, loc, plain, d));
      auto made = AllocTensorOp::create(b, loc, tensor, sizes, copy ? plain : Value());
      return idr::heldAs(b, loc, made.getResult(), value.getType());
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

    numAllocs += static_cast<uint64_t>(statistics.numBufferAlloc);
    numInPlace += static_cast<uint64_t>(statistics.numTensorInPlace);
    numCopies += static_cast<uint64_t>(statistics.numTensorOutOfPlace);
  }
};

} // namespace
