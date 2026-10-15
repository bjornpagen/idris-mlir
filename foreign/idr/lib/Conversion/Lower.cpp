// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-lower, which takes idr and the memrefs of bufferization to func,
// arith, math, scf, ub and llvm. Phase 0, on the module: the program's
// functions as func.func under their mangled names, once the facts handed
// to LLVM are read. Then each function on its own, in parallel: phase 1, its
// matches as scf and its views of memrefs as offsets, sizes and strides,
// still on idr types; phase 2, the conversion of every idr op and type and
// every memref into the layouts of Layouts. Then, on the module, what the
// functions' lowering wrote (the runtime's declarations and the static
// data), in name order, and the facts at function boundaries.

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

#include "mlir/Analysis/DataLayoutAnalysis.h"
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
#include "mlir/IR/AttrTypeSubElements.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/IR/Threading.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Transforms/DialectConversion.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"
#include "mlir/Transforms/WalkPatternRewriteDriver.h"
#include "llvm/ADT/DenseSet.h"
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

// A closure left in a constant. A constant is a graph, not a tree: `seen`
// holds what has been read, so a part that many paths share is read once.
// A con's cells are read in turn, a plain con's one cell or each cell of a
// run, and then a run's tail.
bool functionClosure(Attribute value, DenseSet<Attribute> &seen) {
  if (!seen.insert(value).second)
    return false;
  if (isa<ClosureAttr>(value))
    return true;
  auto con = dyn_cast<ConAttr>(value);
  if (!con)
    return false;
  for (ArrayAttr cell : con.getCells())
    for (Attribute field : cell)
      if (functionClosure(field, seen))
        return true;
  return con.isRun() && functionClosure(con.getTail(), seen);
}

// idr-defunctionalize has made every closure and every suspension of the
// program a sum: one left here is one a pass after it made.
LogicalResult checkNoClosures(ModuleOp module) {
  DenseSet<Attribute> seen;
  // A lazy type anywhere in a type (an array of lazy values too), and in a
  // type an attribute holds (a function's type, a constructor's fields),
  // each read once.
  AttrTypeWalker lazy;
  lazy.addWalk([](LazyType) { return WalkResult::interrupt(); });
  auto isLazy = [&](Type type) { return lazy.walk(type).wasInterrupted(); };
  WalkResult result = module.walk([&](Operation *op) {
    bool closure = isa<ClosureOp, ApplyOp>(op);
    if (auto constant = dyn_cast<ConstantOp>(op))
      closure = functionClosure(constant.getValue(), seen);
    bool suspension = isa<SuspendOp>(op) || llvm::any_of(op->getResultTypes(), isLazy) ||
                      lazy.walk(op->getAttrDictionary()).wasInterrupted();
    for (Region &region : op->getRegions())
      for (Block &block : region)
        suspension = suspension || llvm::any_of(block.getArgumentTypes(), isLazy);
    if (!closure && !suspension)
      return WalkResult::advance();
    op->emitError("internal error: idr-lower: a ")
        << (closure ? "closure" : "lazy value") << " is left after idr-defunctionalize";
    return WalkResult::interrupt();
  });
  return failure(result.wasInterrupted());
}

// What converts one run of the module's functions in phase 2, in module
// order: everything a conversion writes outside its function goes into the
// Runtime, which is the worker's own.
struct Worker {
  Worker(ModuleOp module, const Layouts &layouts, const DataLayoutAnalysis &dataLayouts,
         const Fields &fields, const Memos &memos,
         const DenseMap<StringAttr, memref::GlobalOp> &globals);

  Runtime runtime;
  TypeConverter converter;
  ConversionTarget target;
  FrozenRewritePatternSet patterns;
};

// Every idr op and type and every memref, taken apart into the layouts.
// Upstream keeps what it lowers and vectorizes: the reads and writes of
// words in buffers, and the linalg ops over words, which get a buffer's
// memref from its components. Every other op of a function is one of the
// dialects the lowering gives, or the conversion fails, the compiler's
// error.
Worker::Worker(ModuleOp module, const Layouts &layouts, const DataLayoutAnalysis &dataLayouts,
               const Fields &fields, const Memos &memos,
               const DenseMap<StringAttr, memref::GlobalOp> &globals)
    : runtime(module, layouts, dataLayouts), target(*module.getContext()) {
  MLIRContext *ctx = module.getContext();
  converter.addConversion([](Type type) { return type; });
  converter.addConversion(
      [&layouts](Type type, SmallVectorImpl<Type> &out) -> std::optional<LogicalResult> {
        if (type.getDialect().getNamespace() != IdrDialect::getDialectNamespace() &&
            !isa<MemRefType>(type))
          return std::nullopt;
        llvm::append_range(out, layouts.components(type));
        return success();
      });
  converter.addSourceMaterialization(
      [this](OpBuilder &b, Type type, ValueRange inputs, Location loc) -> Value {
        auto memref = dyn_cast<MemRefType>(type);
        return memref ? toMemref(b, loc, runtime, memref, inputs) : Value();
      });

  target.addIllegalDialect<IdrDialect, memref::MemRefDialect>();
  target.addLegalDialect<arith::ArithDialect, math::MathDialect, LLVM::LLVMDialect,
                         cf::ControlFlowDialect, scf::SCFDialect, ub::UBDialect,
                         affine::AffineDialect>();
  target.addLegalOp<UnrealizedConversionCastOp>();
  target.addDynamicallyLegalOp<memref::LoadOp>(
      [](memref::LoadOp op) { return holdsWords(op.getMemRefType()); });
  target.addDynamicallyLegalOp<memref::StoreOp>(
      [](memref::StoreOp op) { return holdsWords(op.getMemRefType()); });
  target.addDynamicallyLegalDialect<linalg::LinalgDialect>([](Operation *op) {
    return llvm::all_of(op->getOperandTypes(), [](Type type) {
      auto memref = dyn_cast<MemRefType>(type);
      return !memref || holdsWords(memref);
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
  populateFunctionOpInterfaceTypeConversionPattern<func::FuncOp>(set, converter);
  populateCallOpTypeConversionPattern(set, converter);
  populateReturnOpTypeConversionPattern(set, converter);
  scf::populateSCFStructuralTypeConversionsAndLegality(converter, set, target);
  populateCountingPatterns(set, converter, layouts, runtime, fields);
  populateBigPatterns(set, converter, layouts, runtime);
  populateArrayPatterns(set, converter, layouts, runtime, globals);
  populateMemrefPatterns(set, converter, layouts, runtime);
  populateBufferPatterns(set, converter, layouts, runtime);
  populateStringPatterns(set, converter, layouts, runtime);
  populateCellPatterns(set, converter, layouts, runtime);
  populateScalarPatterns(set, converter, layouts, runtime);
  populateRuntimeCallPatterns(set, converter, layouts, runtime);
  populateCheckPatterns(set, converter, layouts, runtime);
  populateLazyPatterns(set, converter, layouts, runtime, memos);
  patterns = FrozenRewritePatternSet(std::move(set));
}

// Phases 1 and 2 of one function. The views of memrefs become an offset,
// sizes and strides read from their source, in upstream's terms (its
// metadata expansion, with folding, merged constants and region
// simplification off, so that nothing but the views changes), which phase 2
// then takes apart like any memref.
LogicalResult lowerFunction(func::FuncOp fn, const FrozenRewritePatternSet &matches,
                            const FrozenRewritePatternSet &views, Worker &worker) {
  IDR_ZONE_IN("idr-lower function", Conversion);
  walkAndApplyPatterns(fn, matches);
  GreedyRewriteConfig config;
  config.enableFolding(false).enableConstantCSE(false).setRegionSimplificationLevel(
      GreedySimplifyRegionLevel::Disabled);
  if (failed(applyPatternsGreedily(fn, views, config)))
    return fn.emitError("internal error: idr-lower: the views of memrefs did not settle");
  ConversionConfig conversion;
  conversion.allowPatternRollback = false;
  return applyFullConversion(fn, worker.target, worker.patterns, conversion);
}

struct Lower : idr::impl::IdrLowerBase<Lower> {
  using IdrLowerBase::IdrLowerBase;

  void runOnOperation() override {
    ModuleOp module = getOperation();
    MLIRContext *ctx = &getContext();
    if (failed(checkNoClosures(module)))
      return signalPassFailure();
    // Every symbol the lowering adds goes through this one table, after
    // the functions are converted: phase 0 renames each function in it, and
    // the merge enters each declaration and global. While the functions are
    // converted nothing writes it.
    SymbolTable &symbols = getAnalysis<SymbolTable>();
    const Layouts &layouts = getAnalysis<Layouts>();
    if (failed(layouts.valid()))
      return signalPassFailure();
    const DataLayoutAnalysis &dataLayouts = getAnalysis<DataLayoutAnalysis>();
    Facts facts(module, symbols);

    // Phase 0.
    RewritePatternSet functionSet(ctx);
    populateFuncToFuncPatterns(functionSet, symbols);
    walkAndApplyPatterns(module, std::move(functionSet));

    Fields fields(module);
    FailureOr<Memos> memos = readMemos(module, symbols);
    if (failed(memos))
      return signalPassFailure();
    DenseMap<StringAttr, memref::GlobalOp> globals;
    for (auto global : module.getOps<memref::GlobalOp>())
      globals[global.getSymNameAttr()] = global;
    RewritePatternSet matchSet(ctx);
    populateMatchPatterns(matchSet);
    FrozenRewritePatternSet matches(std::move(matchSet));
    RewritePatternSet viewSet(ctx);
    memref::populateExpandStridedMetadataPatterns(viewSet);
    FrozenRewritePatternSet views(std::move(viewSet));

    // The functions in module order, cut into one run per thread the pool
    // has, each run lowered by a worker of its own, so which worker lowers a
    // function is a fact of the module and nothing is claimed.
    SmallVector<func::FuncOp> functions(module.getOps<func::FuncOp>());
    size_t threads = ctx->isMultithreadingEnabled() ? ctx->getThreadPool().getMaxConcurrency() : 1;
    size_t runs = std::max<size_t>(1, std::min(threads, functions.size()));
    SmallVector<std::unique_ptr<Worker>> workers(runs);
    LogicalResult lowered =
        failableParallelForEach(ctx, llvm::seq<size_t>(0, runs), [&](size_t run) {
          profile::ThreadTrace trace;
          workers[run] =
              std::make_unique<Worker>(module, layouts, dataLayouts, fields, *memos, globals);
          size_t first = run * functions.size() / runs;
          size_t last = (run + 1) * functions.size() / runs;
          for (func::FuncOp fn : ArrayRef(functions).slice(first, last - first))
            if (failed(lowerFunction(fn, matches, views, *workers[run])))
              return failure();
          return success();
        });
    if (failed(lowered))
      return signalPassFailure();

    SmallVector<Runtime *> runtimes;
    for (const std::unique_ptr<Worker> &worker : workers)
      runtimes.push_back(&worker->runtime);
    if (failed(Runtime::merge(module, symbols, runtimes)))
      return signalPassFailure();
    // A constant array is static data now, under its content's name.
    for (auto global : llvm::make_early_inc_range(module.getOps<memref::GlobalOp>()))
      symbols.erase(global);
    facts.apply(layouts);
  }
};

} // namespace

} // namespace idr::conversion
