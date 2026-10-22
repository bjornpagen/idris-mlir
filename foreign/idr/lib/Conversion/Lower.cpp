// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-lower, which takes the program's functions out of idr into the LLVM
// dialect, and the dialects upstream's conversions to LLVM take after it.
// Every runtime function was declared and every static datum made before
// it (idr-lower-runtime, idr-lower-statics), so a function's lowering
// writes nothing outside the function, and every function is lowered at
// once.
//
// First the rows are written, last before they become LLVM's attributes.
// Then, on the program: each call that gives a lifetime where its callee
// asks a view gives the view; each function's account opened and told
// where it keeps one, and its lifetimes made ready (its cursor parameters
// in slots, its rooms laid out), every function at once;
// then every function's name mangled and the function made an llvm.func
// (phase 0). Then each function on its own, in parallel: its exchanges of
// memo cells as their steps, its matches as scf and its views of memrefs
// as offsets, sizes and strides, still on idr types (phase 1); every op
// and type of ours converted into the layouts of Layouts, every memref op
// by upstream's patterns or, where the memory is a cell of ours, our own,
// and every math op whose fold would compute on the compiling machine by
// upstream's intrinsic (phase 2); and every region made the blocks
// upstream's scf patterns make (phase 3). The program is lowered.

#include "idr/Conversion/Lower/Lower.h"

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Traits.h"
#include "idr/Analysis/Constants.h"
#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/Analysis/Solver/Work.h"
#include "idr/Conversion/Arrays.h"
#include "idr/Conversion/Matches.h"
#include "idr/Conversion/Passes.h"
#include "idr/Conversion/Patterns.h"
#include "idr/Conversion/Runtime.h"
#include "idr/Support/Profile.h"
#include "idr/Transforms/Effects.h"
#include "idr/Transforms/Pipeline.h"

#include "mlir/Analysis/DataLayoutAnalysis.h"
#include "mlir/Conversion/LLVMCommon/LoweringOptions.h"
#include "mlir/Conversion/MathToLLVM/MathToLLVM.h"
#include "mlir/Conversion/MemRefToLLVM/MemRefToLLVM.h"
#include "mlir/Dialect/Affine/IR/AffineOps.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlow.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/Linalg/IR/Linalg.h"
#include "mlir/Dialect/Math/IR/Math.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/MemRef/Transforms/Transforms.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/SCF/Transforms/Patterns.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/Threading.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Transforms/DialectConversion.h"
#include "mlir/Transforms/WalkPatternRewriteDriver.h"

#include <memory>

namespace idr {
#define GEN_PASS_DEF_IDRLOWER
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::conversion {

namespace {

// An op whose result is its first operand at run time (a change of grade,
// of linearity, or of what a word's type says), lowered to that operand's
// components, the lifetimes it states after it being no value: one pattern
// for every op with the trait.
template <template <typename> class Trait>
struct LowerAsOperand : OpTraitConversionPattern<Trait> {
  using OpTraitConversionPattern<Trait>::OpTraitConversionPattern;
  LogicalResult matchAndRewrite(Operation *op, ArrayRef<ValueRange> operands,
                                ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOpWithMultiple(op, {SmallVector<Value>(operands.front())});
    return success();
  }
};

// What every function's lowering reads, made once, before any function is
// lowered and shared by all: the converter, the target and the patterns.
// None is written while the functions are lowered.
struct Lowering {
  Lowering(ProgramOp program, const Layouts &layouts, Runtime &runtime,
           const DenseMap<StringAttr, ConstantArray> &arrays);

  TypeConverter converter;
  ConversionTarget target;
  FrozenRewritePatternSet structure;
  FrozenRewritePatternSet patterns;
  FrozenRewritePatternSet tells;
};

// Every op and type of ours and every memref op, taken apart into the
// layouts. Two converters meet in a function: ours, which takes a value of
// ours and a memref at a boundary or in a cell apart into components, and
// upstream's, whose memref patterns work on the descriptor; the conversion
// builds each from the other where a use needs it. Upstream keeps what it
// vectorizes: the reads and writes of words in buffers, and the linalg ops
// over words. Every other op of a function is one of the dialects the
// lowering gives, or the conversion fails, the compiler's error.
Lowering::Lowering(ProgramOp program, const Layouts &layouts, Runtime &runtime,
                   const DenseMap<StringAttr, ConstantArray> &arrays)
    : target(*program.getContext()) {
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
  target.addLegalDialect<arith::ArithDialect, LLVM::LLVMDialect, cf::ControlFlowDialect,
                         scf::SCFDialect, ub::UBDialect, affine::AffineDialect>();
  // A math op whose fold would compute on the compiling machine's libm (the
  // generated never-folded list) is lowered here, where nothing folds, to
  // upstream's intrinsic, so no upstream driver after this pass meets it to
  // fold; every other math op stays for upstream's lowering.
  target.addDynamicallyLegalDialect<math::MathDialect>(
      [](Operation *op) { return foldingOf(op) == Folding::Folds; });
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
  // A function's own op is legal once its entry block's arguments are.
  target.addDynamicallyLegalOp<LLVM::LLVMFuncOp>([this](LLVM::LLVMFuncOp fn) {
    return fn.isExternal() || converter.isLegal(fn.getBody().front().getArgumentTypes());
  });

  tells = accountPatterns(ctx, runtime);

  RewritePatternSet structureSet(ctx);
  populateMatchPatterns(structureSet);
  memref::populateExpandStridedMetadataPatterns(structureSet);
  structure = FrozenRewritePatternSet(std::move(structureSet));

  RewritePatternSet set(ctx);
  populateFunctionPatterns(set, converter, layouts, runtime);
  scf::populateSCFStructuralTypeConversionsAndLegality(converter, set, target);
  populateJoinTypeConversions(converter, set, target);
  set.add<LowerAsOperand<NoRuntimeForm>, LowerAsOperand<ResultCarriesOperand>>(converter, ctx);
  populateCountingPatterns(set, converter, layouts, runtime);
  populateLifetimePatterns(set, converter, layouts, runtime);
  populatePackagePatterns(set, converter, layouts, runtime);
  populateBigPatterns(set, converter, layouts, runtime);
  populateArrayPatterns(set, converter, layouts, runtime, arrays);
  populateMemrefPatterns(set, converter, layouts, runtime);
  populateBufferPatterns(set, converter, layouts, runtime);
  populateStringPatterns(set, converter, layouts, runtime);
  populateCellPatterns(set, converter, layouts, runtime);
  populateReindexPatterns(set, converter, layouts, runtime);
  populateValuePatterns(set, converter, layouts, runtime);
  populateDestinationPatterns(set, converter, layouts, runtime);
  populateScalarPatterns(set, converter, layouts, runtime);
  populateRuntimeCallPatterns(set, converter, layouts, runtime);
  populateCheckPatterns(set, converter, layouts, runtime);
  populateMemoPatterns(set, converter, layouts, runtime);
  // Upstream's own lowering of each math op to its LLVM intrinsic, with no
  // `nobuiltin` and no `strictfp`; only the ops the target leaves illegal,
  // the never-folded ones, meet it.
  populateMathToLLVMConversionPatterns(descriptors, set);
  // Upstream's memref patterns, but for a constant's: a constant array is a
  // cell of ours, static data with its header, where upstream would make a
  // global of its own. The options make no allocation pattern: an
  // allocation is the runtime's.
  RewritePatternSet upstream(ctx);
  populateFinalizeMemRefToLLVMConversionPatterns(descriptors, upstream);
  OperationName getGlobal(memref::GetGlobalOp::getOperationName(), ctx);
  OperationName global(memref::GlobalOp::getOperationName(), ctx);
  for (std::unique_ptr<RewritePattern> &pattern : upstream.getNativePatterns())
    if (pattern->getRootKind() != getGlobal && pattern->getRootKind() != global)
      set.add(std::move(pattern));
  patterns = FrozenRewritePatternSet(std::move(set));
}

// Phases 1 to 3 of one function. Phase 1 makes each exchange of a memo
// cell its steps, so the exchange has one lowering, its steps', and nothing
// is left at its end to run; then one walk: the matches become scf, and the
// views of memrefs an offset, sizes and strides read from their source in
// upstream's terms, each op once, new ops untouched, so there is nothing to
// iterate to. Splitting moves the exchange's code out of its region, and
// every call in it was already no tail, since the cell is written after it,
// and still is, the store following it in its block.
LogicalResult lowerFunction(LLVM::LLVMFuncOp fn, const Lowering &lowering) {
  IDR_ZONE_IN("idr-lower function", Conversion);
  IRRewriter rewriter(fn.getContext());
  fn.walk([&](MemoRunOp exchange) { exchange.split(rewriter); });
  walkAndApplyPatterns(fn, lowering.structure);
  ConversionConfig conversion;
  conversion.allowPatternRollback = false;
  // Without rollback an op's operands are already the converted values
  // when the driver would fold it, so an idr op's fold would read an LLVM
  // value as one of its own types. Every op here has a pattern, and the
  // optimizer folded what folds before the lowering.
  conversion.foldingMode = DialectConversionFoldingMode::Never;
  if (failed(applyFullConversion(fn, lowering.target, lowering.patterns, conversion)))
    return failure();
  return lowerControlFlow(fn);
}

struct Lower : idr::impl::IdrLowerBase<Lower> {
  using IdrLowerBase::IdrLowerBase;

  void runOnProgram(ProgramOp program) {
    MLIRContext *ctx = &getContext();
    // The rows are written last here, before they become LLVM's
    // attributes, by the one writer of rows, its work the pass's.
    solver::Work work;
    const solver::ProgramGraph &graph = getAnalysis<solver::ProgramGraph>();
    rows::write(program, graph, work);
    numWork += work.steps();
    const Layouts &layouts = getAnalysis<Layouts>();
    // Read from the module's data layout once, here: a data layout fills
    // its caches as it is asked, so no function's lowering may ask it.
    LowerToLLVMOptions options(ctx, getAnalysis<DataLayoutAnalysis>().getAtOrAbove(program));
    options.allocLowering = LowerToLLVMOptions::AllocLowering::None;
    Runtime runtime(ctx, layouts, options);

    // Each memref.global read once as the constant array it must be.
    DenseMap<StringAttr, ConstantArray> arrays;
    for (auto global : program->getRegion(0).getOps<memref::GlobalOp>()) {
      FailureOr<ConstantArray> array = ConstantArray::of(global);
      if (failed(array))
        return signalPassFailure();
      arrays.try_emplace(global.getSymNameAttr(), *array);
    }

    Lowering lowering(program, layouts, runtime, arrays);
    // Each callee is resolved through the program graph, the one index of
    // calls, until the functions become LLVM's below.
    viewsWhereAsked(program, graph);
    SmallVector<FuncOp> sources(program->getRegion(0).getOps<FuncOp>());
    // The account first: its points are read off the function as the
    // passes left it, before its lifetimes put anything into it.
    if (failed(failableParallelForEach(ctx, sources, [&](FuncOp fn) {
          keepAccount(fn, lowering.tells, layouts, runtime);
          return prepareLifetimes(fn, graph, layouts);
        })))
      return signalPassFailure();
    SmallVector<LLVM::LLVMFuncOp> functions =
        lowerSignatures(program, lowering.converter, layouts);
    if (failed(failableParallelForEach(ctx, functions, [&](LLVM::LLVMFuncOp fn) {
          profile::ThreadTrace trace;
          return lowerFunction(fn, lowering);
        })))
      return signalPassFailure();
    // A constant array is static data now, under its content's name.
    for (memref::GlobalOp global :
         llvm::make_early_inc_range(program->getRegion(0).getOps<memref::GlobalOp>()))
      global.erase();
  }
};

} // namespace

} // namespace idr::conversion
