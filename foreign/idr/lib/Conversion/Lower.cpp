// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-lower, which takes idr to func, arith, math, scf, ub and llvm: phase
// 0 (the program's functions as func.func under their mangled names, once
// the facts handed to LLVM are read), phase 1 (matches and loops over
// arrays, on idr types), then phase 2, the conversion of every idr op and
// type into the layouts of Layouts, then the facts at function boundaries.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Layout.h"
#include "idr/Conversion/ArrayLoops.h"
#include "idr/Conversion/ArrayView.h"
#include "idr/Conversion/Facts.h"
#include "idr/Conversion/Fields.h"
#include "idr/Conversion/FuncToFunc.h"
#include "idr/Conversion/Matches.h"
#include "idr/Conversion/Passes.h"
#include "idr/Conversion/Patterns.h"
#include "idr/Conversion/Runtime.h"
#include "idr/Support/Profile.h"

#include "mlir/Analysis/DataLayoutAnalysis.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlow.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/Func/Transforms/FuncConversions.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/Linalg/IR/Linalg.h"
#include "mlir/Dialect/Math/IR/Math.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/SCF/Transforms/Patterns.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/AttrTypeSubElements.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Transforms/DialectConversion.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"
#include "mlir/Transforms/WalkPatternRewriteDriver.h"
#include "llvm/ADT/DenseSet.h"

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
// program a sum, and reported as unsupported each one it could not follow:
// one left here is one a pass after it made.
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

// Phase 2: every idr op and type, taken apart into the layouts. A legal op
// that still holds an array of words (a linalg op over it, made by phase 1)
// gets the array's view of its cell and sizes.
LogicalResult convert(ModuleOp module, const Layouts &layouts, Runtime &runtime,
                      const Fields &fields) {
  IDR_ZONE_IN("idr-lower phase 2", Conversion);
  MLIRContext *ctx = module.getContext();
  TypeConverter converter;
  converter.addConversion([](Type type) { return type; });
  converter.addConversion(
      [&](Type type, SmallVectorImpl<Type> &out) -> std::optional<LogicalResult> {
        if (type.getDialect().getNamespace() != IdrDialect::getDialectNamespace() &&
            !isArray(type))
          return std::nullopt;
        llvm::append_range(out, layouts.components(type));
        return success();
      });
  converter.addSourceMaterialization(
      [&](OpBuilder &b, Type type, ValueRange inputs, Location loc) -> Value {
        if (!isArray(type) || inputs.size() != layouts.components(type).size())
          return nullptr;
        return arrayView(b, loc, runtime, cast<MemRefType>(type), inputs);
      });

  ConversionTarget target(*ctx);
  target.addIllegalDialect<IdrDialect>();
  target.addLegalDialect<arith::ArithDialect, math::MathDialect, LLVM::LLVMDialect,
                         cf::ControlFlowDialect, memref::MemRefDialect, linalg::LinalgDialect>();
  // The one memref op idr hands the lowering, an array's length, becomes
  // the length beside the cell; the loads and stores the lowering itself
  // makes on an array's view stay for convert-to-llvm.
  target.addIllegalOp<memref::DimOp>();
  target.addLegalOp<UnrealizedConversionCastOp, ub::UnreachableOp>();
  // The declarations are erased after the conversion.
  target.addLegalOp<DataOp, CtorOp>();
  target.addDynamicallyLegalOp<ub::PoisonOp>(
      [&](ub::PoisonOp op) { return converter.isLegal(op.getType()); });
  target.addDynamicallyLegalOp<arith::SelectOp>(
      [&](arith::SelectOp op) { return converter.isLegal(op.getType()); });
  target.addDynamicallyLegalOp<func::FuncOp>([&](func::FuncOp op) {
    return converter.isSignatureLegal(op.getFunctionType()) &&
           converter.isLegal(&op.getBody());
  });
  target.addDynamicallyLegalOp<func::CallOp, func::ReturnOp>(
      [&](Operation *op) { return converter.isLegal(op); });

  RewritePatternSet patterns(ctx);
  populateFunctionOpInterfaceTypeConversionPattern<func::FuncOp>(patterns, converter);
  populateCallOpTypeConversionPattern(patterns, converter);
  populateReturnOpTypeConversionPattern(patterns, converter);
  scf::populateSCFStructuralTypeConversionsAndLegality(converter, patterns, target);
  populateCountingPatterns(patterns, converter, layouts, runtime, fields);
  populateBigPatterns(patterns, converter, layouts, runtime);
  populateArrayPatterns(patterns, converter, layouts, runtime);
  populateBufferPatterns(patterns, converter, layouts, runtime);
  populateStringPatterns(patterns, converter, layouts, runtime);
  populateCellPatterns(patterns, converter, layouts, runtime);
  populateScalarPatterns(patterns, converter, layouts, runtime);
  populateRuntimeCallPatterns(patterns, converter, layouts, runtime);
  populateCheckPatterns(patterns, converter, layouts, runtime);
  populateLazyPatterns(patterns, converter, layouts, runtime);

  ConversionConfig config;
  config.allowPatternRollback = false;
  return applyPartialConversion(module, target, std::move(patterns), config);
}

struct Lower : idr::impl::IdrLowerBase<Lower> {
  using IdrLowerBase::IdrLowerBase;

  void runOnOperation() override {
    ModuleOp module = getOperation();
    MLIRContext *ctx = &getContext();
    if (failed(checkNoClosures(module)))
      return signalPassFailure();
    // Every lookup of a declaration, and every symbol the lowering adds,
    // goes through this one table: phase 0 renames each function in it,
    // and the runtime enters each declaration and global it writes.
    SymbolTable &symbols = getAnalysis<SymbolTable>();
    const Layouts &layouts = getAnalysis<Layouts>();
    if (failed(layouts.valid()))
      return signalPassFailure();
    Runtime runtime(module, layouts, symbols, getAnalysis<DataLayoutAnalysis>());
    Facts facts(module, symbols);

    // Phase 0, then phase 1.
    RewritePatternSet functions(ctx);
    populateFuncToFuncPatterns(functions, symbols);
    walkAndApplyPatterns(module, std::move(functions));
    RewritePatternSet matches(ctx);
    populateMatchPatterns(matches, symbols);
    walkAndApplyPatterns(module, std::move(matches));
    RewritePatternSet loops(ctx);
    populateArrayLoopPatterns(loops);
    // Only these two rewrites, outermost first: no folding, no merged
    // constants, no region simplification. A loop the driver left would be
    // an idr op phase 2 refuses.
    (void)applyPatternsGreedily(module, std::move(loops),
                                GreedyRewriteConfig()
                                    .setUseTopDownTraversal()
                                    .enableFolding(false)
                                    .enableConstantCSE(false)
                                    .setRegionSimplificationLevel(
                                        GreedySimplifyRegionLevel::Disabled));
    // Read from the ops as the conversion will meet them.
    Fields fields(module);
    if (failed(convert(module, layouts, runtime, fields)))
      return signalPassFailure();

    runtime.finish();
    for (auto data : llvm::make_early_inc_range(module.getOps<DataOp>()))
      symbols.erase(data);
    // The program's mark has served its purpose; LLVM's translation refuses
    // an attribute of a dialect it cannot translate. Phase 0 and phase 2 left
    // no other: the facts went with idr.func, a stack mark with its idr.con.
    IdrDialect::ProgramAttrHelper program(ctx);
    if (program.isAttrPresent(module))
      program.removeAttr(module);
    facts.apply(layouts);
  }
};

} // namespace

} // namespace idr::conversion
