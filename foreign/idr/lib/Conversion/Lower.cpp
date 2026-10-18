// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-lower, which takes the program's idr and the memrefs of
// bufferization to func, arith, math, scf, ub and llvm, where the program
// is. Phase 0, on the program: its functions as func.func under their
// mangled names. Then each function on its own, in parallel: phase 1, its
// matches as scf and its views of memrefs as offsets, sizes and strides,
// still on idr types; phase 2, the conversion of every idr op and type into
// the layouts of Layouts, and of every memref op by upstream's memref
// patterns or, where the memory is a cell of ours, our own, its signature
// with the facts its components give LLVM. Then, on the program, what the
// functions' lowering wrote (the runtime's declarations and the static
// data), in name order; the program is lowered.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Layout.h"
#include "idr/Conversion/Arrays.h"
#include "idr/Conversion/Facts.h"
#include "idr/Conversion/Fields.h"
#include "idr/Conversion/FuncToFunc.h"
#include "idr/Conversion/Matches.h"
#include "idr/Conversion/Passes.h"
#include "idr/Conversion/Patterns.h"
#include "idr/Conversion/Runtime.h"
#include "idr/Support/Profile.h"
#include "idr/Transforms/Pipeline.h"

#include "mlir/Analysis/DataLayoutAnalysis.h"
#include "mlir/Conversion/LLVMCommon/LoweringOptions.h"
#include "mlir/Conversion/MemRefToLLVM/MemRefToLLVM.h"
#include "mlir/Dialect/Affine/IR/AffineOps.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlow.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/Func/Transforms/FuncConversions.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/Linalg/IR/Linalg.h"
#include "mlir/Dialect/Math/IR/Math.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/MemRef/Transforms/Transforms.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/SCF/Transforms/Patterns.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/IR/Threading.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Transforms/DialectConversion.h"
#include "mlir/Transforms/WalkPatternRewriteDriver.h"
#include "llvm/ADT/Sequence.h"

#include <algorithm>
#include <memory>

namespace idr {
#define GEN_PASS_DEF_IDRLOWER
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::conversion {

namespace {

// An op with no runtime form (NoRuntimeForm): its result is its first
// operand at run time, a change of grade, linearity or kind, so it lowers to
// that operand's components. One pattern for every op with the trait.
struct LowerNoRuntimeForm : OpTraitConversionPattern<NoRuntimeForm> {
  using OpTraitConversionPattern::OpTraitConversionPattern;
  LogicalResult matchAndRewrite(Operation *op, ArrayRef<ValueRange> operands,
                                ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOpWithMultiple(op, {SmallVector<Value>(operands.front())});
    return success();
  }
};

// What converts one run of the program's functions in phase 2, in program
// order: everything a conversion writes outside its function goes into the
// Runtime, which is the worker's own.
struct Worker {
  Worker(ProgramOp program, const Layouts &layouts, const LowerToLLVMOptions &options,
         const Fields &fields, const DenseMap<StringAttr, ConstantArray> &arrays);

  Runtime runtime;
  TypeConverter converter;
  ConversionTarget target;
  FrozenRewritePatternSet patterns;
};

// Every idr op and type and every memref op, taken apart into the layouts.
// Two converters meet in a function: ours, which takes an idr value and a
// memref at a boundary or in a cell apart into components, and upstream's,
// whose memref patterns work on the descriptor; the conversion builds each
// from the other where a use needs it. Upstream keeps what it vectorizes:
// the reads and writes of words in buffers, and the linalg ops over words.
// Every other op of a function is one of the dialects the lowering gives,
// or the conversion fails, the compiler's error.
Worker::Worker(ProgramOp program, const Layouts &layouts, const LowerToLLVMOptions &options,
               const Fields &fields, const DenseMap<StringAttr, ConstantArray> &arrays)
    : runtime(program.getLoc(), layouts, options), target(*program.getContext()) {
  MLIRContext *ctx = program.getContext();
  converter.addConversion([](Type type) { return type; });
  converter.addConversion(
      [&layouts](Type type, SmallVectorImpl<Type> &out) -> std::optional<LogicalResult> {
        if (!isa<IdrDialect>(type.getDialect()) && !isa<MemRefType>(type))
          return std::nullopt;
        for (const layout::Component &component : layouts.components(type))
          out.push_back(component.type);
        return success();
      });
  LLVMTypeConverter &descriptors = runtime.llvmTypeConverter();
  addMemrefConversions(converter, descriptors, layouts);

  target.addIllegalDialect<IdrDialect, memref::MemRefDialect>();
  target.addLegalDialect<arith::ArithDialect, math::MathDialect, LLVM::LLVMDialect,
                         cf::ControlFlowDialect, scf::SCFDialect, ub::UBDialect,
                         affine::AffineDialect>();
  target.addLegalOp<UnrealizedConversionCastOp>();
  target.addDynamicallyLegalOp<memref::LoadOp>(
      [](memref::LoadOp op) { return leftToUpstream(op.getMemRefType()); });
  target.addDynamicallyLegalOp<memref::StoreOp>(
      [](memref::StoreOp op) { return leftToUpstream(op.getMemRefType()); });
  target.addDynamicallyLegalDialect<linalg::LinalgDialect>([](Operation *op) {
    return llvm::all_of(op->getOperandTypes(), [](Type type) {
      auto memref = dyn_cast<MemRefType>(type);
      return !memref || leftToUpstream(memref);
    });
  });
  target.addDynamicallyLegalOp<ub::PoisonOp>(
      [this](ub::PoisonOp op) { return converter.isLegal(op.getType()); });
  target.addDynamicallyLegalOp<arith::SelectOp>(
      [this](arith::SelectOp op) { return converter.isLegal(op.getType()); });
  target.addDynamicallyLegalOp<func::FuncOp>([this](func::FuncOp op) {
    return converter.isSignatureLegal(op.getFunctionType()) && converter.isLegal(&op.getBody());
  });
  target.addDynamicallyLegalOp<func::CallOp, func::ReturnOp>(
      [this](Operation *op) { return converter.isLegal(op); });

  RewritePatternSet set(ctx);
  populateSignaturePatterns(set, converter, layouts);
  populateCallOpTypeConversionPattern(set, converter);
  populateReturnOpTypeConversionPattern(set, converter);
  scf::populateSCFStructuralTypeConversionsAndLegality(converter, set, target);
  set.add<LowerNoRuntimeForm>(converter, ctx);
  populateCountingPatterns(set, converter, layouts, runtime);
  populateBigPatterns(set, converter, layouts, runtime);
  populateArrayPatterns(set, converter, layouts, runtime, arrays);
  populateMemrefPatterns(set, converter, layouts, runtime);
  populateBufferPatterns(set, converter, layouts, runtime);
  populateStringPatterns(set, converter, layouts, runtime);
  populateCellPatterns(set, converter, layouts, runtime, fields);
  populateScalarPatterns(set, converter, layouts, runtime);
  populateRuntimeCallPatterns(set, converter, layouts, runtime);
  populateCheckPatterns(set, converter, layouts, runtime);
  populateMemoPatterns(set, converter, layouts, runtime);
  // Upstream's memref patterns, but for a constant's: a constant array is a
  // cell of ours, static data with its header, where upstream would make a
  // global of its own and write 0xdeadbeef as the allocated pointer. The
  // options make no allocation pattern: an allocation is the runtime's.
  RewritePatternSet upstream(ctx);
  populateFinalizeMemRefToLLVMConversionPatterns(descriptors, upstream);
  OperationName getGlobal(memref::GetGlobalOp::getOperationName(), ctx);
  OperationName global(memref::GlobalOp::getOperationName(), ctx);
  for (std::unique_ptr<RewritePattern> &pattern : upstream.getNativePatterns())
    if (pattern->getRootKind() != getGlobal && pattern->getRootKind() != global)
      set.add(std::move(pattern));
  patterns = FrozenRewritePatternSet(std::move(set));
}

// Phases 1 and 2 of one function. Phase 1 is one walk: the matches become
// scf, and the views of memrefs an offset, sizes and strides read from their
// source in upstream's terms (its metadata expansion, which upstream's
// memref lowering needs first), each op once, new ops untouched, so there
// is nothing to iterate to.
LogicalResult lowerFunction(func::FuncOp fn, const FrozenRewritePatternSet &structure,
                            Worker &worker) {
  IDR_ZONE_IN("idr-lower function", Conversion);
  walkAndApplyPatterns(fn, structure);
  ConversionConfig conversion;
  conversion.allowPatternRollback = false;
  // Without rollback an op's operands are already the converted values
  // when the driver would fold it, so an idr op's fold would read an LLVM
  // value as one of its own types. Every op here has a pattern, and the
  // optimizer folded what folds before the lowering.
  conversion.foldingMode = DialectConversionFoldingMode::Never;
  return applyFullConversion(fn, worker.target, worker.patterns, conversion);
}

LogicalResult lowerProgram(ProgramOp program, const Layouts &layouts,
                           const LowerToLLVMOptions &options,
                           const FrozenRewritePatternSet &structure) {
  MLIRContext *ctx = program.getContext();
  // Phase 0.
  if (failed(lowerFunctions(program)))
    return failure();
  // Every symbol the lowering adds goes through this one table, after the
  // functions are converted: the merge enters each declaration and global.
  // While the functions are converted nothing writes it.
  SymbolTable symbols(program);

  Fields fields(program);
  // Each memref.global is read once as the constant array it must be.
  DenseMap<StringAttr, ConstantArray> arrays;
  for (auto global : program->getRegion(0).getOps<memref::GlobalOp>()) {
    FailureOr<ConstantArray> array = ConstantArray::of(global);
    if (failed(array))
      return failure();
    arrays.try_emplace(global.getSymNameAttr(), *array);
  }

  // The functions in program order, cut into one run per thread the pool
  // has, each run lowered by a worker of its own, so which worker lowers a
  // function is a fact of the program and nothing is claimed.
  SmallVector<func::FuncOp> functions(program->getRegion(0).getOps<func::FuncOp>());
  size_t threads = ctx->isMultithreadingEnabled() ? ctx->getThreadPool().getMaxConcurrency() : 1;
  size_t runs = std::max<size_t>(1, std::min(threads, functions.size()));
  SmallVector<std::unique_ptr<Worker>> workers(runs);
  LogicalResult lowered =
      failableParallelForEach(ctx, llvm::seq<size_t>(0, runs), [&](size_t run) {
        profile::ThreadTrace trace;
        workers[run] = std::make_unique<Worker>(program, layouts, options, fields, arrays);
        size_t first = run * functions.size() / runs;
        size_t last = (run + 1) * functions.size() / runs;
        for (func::FuncOp fn : ArrayRef(functions).slice(first, last - first))
          if (failed(lowerFunction(fn, structure, *workers[run])))
            return failure();
        return success();
      });
  if (failed(lowered))
    return failure();

  SmallVector<Runtime *> runtimes;
  for (const std::unique_ptr<Worker> &worker : workers)
    runtimes.push_back(&worker->runtime);
  if (failed(Runtime::merge(program, symbols, runtimes)))
    return failure();
  // A constant array is static data now, under its content's name.
  for (memref::GlobalOp global :
       llvm::make_early_inc_range(program->getRegion(0).getOps<memref::GlobalOp>()))
    symbols.erase(global);
  return success();
}

struct Lower : idr::impl::IdrLowerBase<Lower> {
  using IdrLowerBase::IdrLowerBase;

  void runOnProgram(ProgramOp program) override {
    ModuleOp module = getOperation();
    MLIRContext *ctx = &getContext();
    const Layouts &layouts = getAnalysis<Layouts>();
    // Read from the module's data layout once, here: a data layout fills
    // its caches as it is asked, so no worker may ask it.
    LowerToLLVMOptions options(ctx, getAnalysis<DataLayoutAnalysis>().getAtOrAbove(module));
    options.allocLowering = LowerToLLVMOptions::AllocLowering::None;
    RewritePatternSet structureSet(ctx);
    populateMatchPatterns(structureSet);
    memref::populateExpandStridedMetadataPatterns(structureSet);
    FrozenRewritePatternSet structure(std::move(structureSet));
    if (failed(lowerProgram(program, layouts, options, structure)))
      return signalPassFailure();
  }
};

} // namespace

} // namespace idr::conversion
