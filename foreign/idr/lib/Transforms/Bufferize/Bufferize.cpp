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
// (idr.array.update), as on mutable memory: the element moves out with the
// buffer's reference and the written value moves in, so a vector's pop
// counts nothing twice.
//
// A buffer is a cell of the runtime: an allocation is memref.alloc, which
// idr-lower makes the runtime's cell, its elements unwritten. One of
// elements that hold references is taken over by counting where it is
// allocated (idr.own.adopt), the one place a buffer is known to be an
// allocation. A copy into
// a buffer just allocated for it is its first write, a placement
// (idr.array.place_copy), which releases nothing; a copy over a buffer that
// holds elements is memref.copy, the runtime's copy, which releases each
// element it overwrites. Both count the references of the elements they
// copy. No ownership deallocation runs: counting frees cells, one
// ownership system and not two.
//
// Every buffer allocated for elements that hold references is written
// whole by its first writer, a placed copy or the generating op whose
// destination it is, both placements: so no store, no copy and no release
// at the buffer's death ever reads a slot nothing wrote, and no allocation
// is filled first. A fresh array of such elements is a generating op's
// destination alone, as the frontend writes it, and an insert over a whole
// array is made that array before the analysis; the buffers are held to it
// after the rewrite.
#include "idr/Transforms/Bufferize.h"

#include "idr/Transforms/BufferizeModels.h"

#include "idr/IR/Arrays.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Tail.h"
#include "idr/Support/Footprint.h"
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
#include "mlir/IR/PatternMatch.h"
#include "mlir/Interfaces/DestinationStyleOpInterface.h"

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

// A buffer, made where One-Shot asks for one. One of elements that hold
// references enters counting where it is made, and only there
// (idr.own.adopt): no other buffer (a slice, a parameter's, one read out of
// a cell) is an allocation, so taking one over anywhere else would count
// its memory twice. Every use reads the adopted buffer, at the bare carrier
// upstream's ops take.
FailureOr<Value> allocate(OpBuilder &b, Location loc, MemRefType type, ValueRange sizes,
                          unsigned alignment) {
  auto made = alignment == 0
                  ? memref::AllocOp::create(b, loc, type, sizes)
                  : memref::AllocOp::create(b, loc, type, sizes, b.getI64IntegerAttr(alignment));
  if (!idr::holdsReferences(type.getElementType()))
    return made.getResult();
  return idr::OwnAdoptOp::create(b, loc, type, made.getResult()).getResult();
}

// A copy of `from` into `to`. A copy into a buffer allocated for it, which
// nothing has used yet, is its first write: its slots hold nothing, so it
// places, releasing none. Every other copy writes over slots that hold
// elements. One-Shot makes both through this one hook, so the hook is
// where the two are told apart, from the allocation it has just made.
LogicalResult copyInto(OpBuilder &b, Location loc, Value from, Value to) {
  if (to.use_empty() && idr::arrays::allocationOf(to))
    idr::ArrayPlaceCopyOp::create(b, loc, from, to);
  else
    memref::CopyOp::create(b, loc, from, to);
  return success();
}

// The first use of every buffer allocated for elements that hold
// references is the destination-style op whose destination it is and which
// does not read it: a placed copy, a tabulation or a scan, which places
// every slot before anything reads or releases one. A fold reads its
// destination, its first accumulators. A buffer used first any other way
// (a store, a view a copy writes through, a fold) would read or release
// slots nothing wrote: the compiler's broken invariant, the frontend's or
// this pass's, named where every allocation is made.
LogicalResult placedFirst(idr::ProgramOp program) {
  WalkResult walked = program.walk([](memref::AllocOp alloc) {
    if (!idr::holdsReferences(alloc.getType().getElementType()))
      return WalkResult::advance();
    // The buffer the program uses: the one counting took over at its
    // allocation, whose one use the adoption is.
    Value buffer = alloc.getResult();
    if (buffer.hasOneUse())
      if (auto adopted = dyn_cast<idr::OwnAdoptOp>(*buffer.getUsers().begin()))
        buffer = adopted.getResult();
    Block *block = alloc->getBlock();
    // The op of the allocation's block that holds the first use: a use
    // dominated by the allocation is in its block or nested in an op of it.
    Operation *first = nullptr;
    for (Operation *user : buffer.getUsers()) {
      Operation *at = block->findAncestorOpInBlock(*user);
      if (!first || at->isBeforeInBlock(first))
        first = at;
    }
    auto writer = dyn_cast_or_null<DestinationStyleOpInterface>(first);
    auto fold = dyn_cast_or_null<idr::LastAxisFoldOpInterface>(first);
    if (writer && llvm::is_contained(writer.getDpsInits(), buffer) &&
        !(fold && llvm::is_contained(fold.getInits(), buffer)))
      return WalkResult::advance();
    InFlightDiagnostic error = alloc.emitError(
        "internal error: idr-bufferize: a buffer of elements that hold references is not "
        "placed whole by its first writer, so a release would read a slot nothing wrote");
    if (first)
      error.attachNote(first->getLoc()) << "first used by " << first->getName();
    return WalkResult::interrupt();
  });
  return failure(walked.wasInterrupted());
}

// Each write into a value array's buffer whose read stands before it
// becomes the element's update (idr::arrays::moveOut), the rule
// idr-simplify keeps for mutable memory. The writes are the program's, so
// the footprint counts them.
void moveElementsOut(idr::ProgramOp program) {
  idr::footprint::Vector<memref::StoreOp> stores;
  program.walk([&](memref::StoreOp store) {
    if (!store.getMemRefType().getMemorySpace())
      stores.push_back(store);
  });
  IRRewriter rewriter(program->getContext());
  for (memref::StoreOp store : stores)
    idr::arrays::moveOut(rewriter, store);
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

  void runOnProgram(idr::ProgramOp program) {
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
    options.allocationFn = allocate;
    options.memCpyFn = copyInto;
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
        })) ||
        failed(placedFirst(program)))
      return signalPassFailure();
    moveElementsOut(program);
    // One-Shot makes each call again on buffers, and may put a cast or a
    // copy after one or fold away what followed it: each call's fact is
    // decided again where it now stands.
    program.walk([](idr::CallOp call) { call.setTailKind(idr::tail::decide(call)); });

    numAllocs += static_cast<uint64_t>(statistics.numBufferAlloc);
    numInPlace += static_cast<uint64_t>(statistics.numTensorInPlace);
    numCopies += static_cast<uint64_t>(statistics.numTensorOutOfPlace);
  }
};

} // namespace
