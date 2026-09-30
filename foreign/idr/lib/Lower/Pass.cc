// idr-lower: idr to func, arith, math, scf, ub and llvm. The layouts,
// runtime calls, static data and patterns it uses are in Lower/.

#include "Lower/Facts.h"
#include "Lower/Patterns.h"

#include "idris_rt.h"

#include "mlir/Dialect/Func/Transforms/FuncConversions.h"
#include "mlir/Dialect/SCF/Transforms/Patterns.h"

using namespace mlir;

namespace idr {
#define GEN_PASS_DEF_IDRLOWER
#include "idr/Passes.h.inc"
} // namespace idr

namespace {

// The root, the only public function, becomes private, and
// @__idr_main runs it. Its type is its kind: `() -> i64` returns the exit
// status; an IO root takes the world, and the status is then 0. Either way
// @__idr_main ends in idris_rt_main_return, which writes pending output
// and, when asked, how many cells are still live. @main hands @__idr_main to
// the runtime's entry, idris_rt_start, which runs it on a reserved stack
// once the CPU has shown it has the features the module's target enables,
// and which ends a status outside 0 to 255 as a crash.
FailureOr<func::FuncOp> findRoot(ModuleOp module) {
  SmallVector<func::FuncOp> roots;
  for (auto fn : module.getOps<func::FuncOp>())
    if (fn.isPublic())
      roots.push_back(fn);
  if (roots.size() != 1 || module.lookupSymbol("main"))
    return module.emitError("internal error: idr-lower needs exactly one public function, "
                            "the root, and no @main");
  return roots.front();
}

// The IDRIS_RT_CPU_FEATURES bits of the features the module's target
// enables. A module with no target states no requirement.
uint64_t requiredCpuFeatures(ModuleOp module) {
  auto target = module->getAttrOfType<LLVM::TargetAttr>(LLVM::LLVMDialect::getTargetAttrName());
  LLVM::TargetFeaturesAttr features = target ? target.getFeatures() : nullptr;
  uint64_t bits = 0;
  if (!features)
    return bits;
#define IDR_REQUIRED_FEATURE(bit, name, ...)                                                    \
  if (features.contains("+" name))                                                             \
    bits |= uint64_t{1} << (bit);
  IDRIS_RT_CPU_FEATURES(IDR_REQUIRED_FEATURE)
#undef IDR_REQUIRED_FEATURE
  return bits;
}

void emitMain(ModuleOp module, func::FuncOp root, bool io, idr::lower::Runtime &runtime) {
  root.setPrivate();
  MLIRContext *ctx = module.getContext();
  OpBuilder b(ctx);
  b.setInsertionPointToEnd(module.getBody());
  Location loc = root.getLoc();
  FunctionType bodyType = b.getFunctionType({}, {b.getI64Type()});
  auto body = func::FuncOp::create(b, loc, "__idr_main", bodyType);
  body.setPrivate();
  auto main = func::FuncOp::create(b, loc, "main", b.getFunctionType({}, {b.getI32Type()}));
  b.setInsertionPointToStart(body.addEntryBlock());
  auto call = func::CallOp::create(b, loc, root, ValueRange{});
  Value status = io ? arith::ConstantOp::create(b, loc, b.getI64IntegerAttr(0)).getResult()
                    : call.getResult(0);
  runtime.call(b, loc, "idris_rt_main_return", Type(), ValueRange{});
  func::ReturnOp::create(b, loc, status);

  // The body is a function value until convert-to-llvm makes it a pointer;
  // the cast between the two disappears then.
  b.setInsertionPointToStart(main.addEntryBlock());
  Value function = func::ConstantOp::create(b, loc, bodyType, body.getSymName());
  Value pointer =
      UnrealizedConversionCastOp::create(b, loc, LLVM::LLVMPointerType::get(ctx), function)
          .getResult(0);
  Value cpu = arith::ConstantOp::create(b, loc, b.getI64IntegerAttr(
                                                    static_cast<int64_t>(requiredCpuFeatures(module))));
  Value started =
      runtime.call(b, loc, "idris_rt_start", b.getI32Type(), ValueRange{pointer, cpu});
  func::ReturnOp::create(b, loc, started);
}

// idr-defunctionalize has made every closure of the program a sum: only
// idr-eval lowers code that still builds, applies or holds a closure.
LogicalResult checkNoClosures(ModuleOp module) {
  WalkResult result = module.walk([](Operation *op) {
    bool closure = isa<idr::ClosureOp, idr::ApplyOp>(op);
    if (auto constant = dyn_cast<idr::ConstantOp>(op))
      constant.getValue().walk([&](idr::ClosureAttr) { closure = true; });
    if (!closure)
      return WalkResult::advance();
    op->emitError("internal error: idr-lower: a closure is left after idr-defunctionalize");
    return WalkResult::interrupt();
  });
  return failure(result.wasInterrupted());
}

struct Lower : idr::impl::IdrLowerBase<Lower> {
  using IdrLowerBase::IdrLowerBase;

  void runOnOperation() override {
    ModuleOp module = getOperation();
    MLIRContext *ctx = &getContext();
    func::FuncOp root;
    bool io = false;
    if (!jit) {
      FailureOr<func::FuncOp> found = findRoot(module);
      if (failed(found))
        return signalPassFailure();
      root = *found;
      io = llvm::any_of(root.getArgumentTypes(), idr::isWorld);
      FunctionType kind = root.getFunctionType();
      if (!io && (kind.getNumInputs() != 0 || kind.getNumResults() != 1 ||
                  !kind.getResult(0).isInteger(64))) {
        root.emitError("internal error: idr-lower: the root neither takes the world nor is "
                       "`() -> i64`");
        return signalPassFailure();
      }
      if (failed(checkNoClosures(module)))
        return signalPassFailure();
    }
    // Every evaluation is metered, total code with a larger budget, so every
    // function counts a tick when entered. idr-eval runs before idr-tail-loops
    // makes loops; a loop of code that need not end ticks at its
    // idr.may_loop.
    if (jit)
      for (auto fn : module.getOps<func::FuncOp>())
        if (!fn.isExternal()) {
          auto b = OpBuilder::atBlockBegin(&fn.getBody().front());
          idr::MayLoopOp::create(b, fn.getLoc());
        }
    FailureOr<idr::lower::Layouts> layouts = idr::lower::Layouts::of(module);
    if (failed(layouts))
      return signalPassFailure();
    idr::lower::Runtime runtime(module, *layouts, jit);
    idr::lower::Facts facts(module);
    // The parameters' idr attributes have served their purpose; the lowered
    // parameters get LLVM's instead (Lower/Facts.h).
    module.walk([](func::FuncOp fn) { fn.removeArgAttrsAttr(); });
    idr::lower::lowerMatches(module);

    TypeConverter converter;
    converter.addConversion([](Type type) { return type; });
    converter.addConversion(
        [&](Type type, SmallVectorImpl<Type> &out) -> std::optional<LogicalResult> {
          if (type.getDialect().getNamespace() != idr::IdrDialect::getDialectNamespace())
            return std::nullopt;
          llvm::append_range(out, layouts->components(type));
          return success();
        });

    ConversionTarget target(*ctx);
    target.addIllegalDialect<idr::IdrDialect>();
    target.addLegalDialect<arith::ArithDialect, math::MathDialect, LLVM::LLVMDialect,
                           cf::ControlFlowDialect>();
    target.addLegalOp<UnrealizedConversionCastOp, ub::UnreachableOp, func::CallIndirectOp,
                      func::ConstantOp>();
    // The declarations are erased after the conversion.
    target.addLegalOp<idr::DataOp, idr::CtorOp>();
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
    idr::lower::populatePatterns(patterns, converter, *layouts, runtime);
    if (jit)
      idr::lower::populateClosurePatterns(patterns, converter, *layouts, runtime);

    ConversionConfig config;
    config.allowPatternRollback = false;
    if (failed(applyPartialConversion(module, target, std::move(patterns), config)))
      return signalPassFailure();

    runtime.emitCode();
    for (auto data : llvm::make_early_inc_range(module.getOps<idr::DataOp>()))
      data.erase();
    // The idr attributes have served their purpose; LLVM's translation
    // refuses attributes of a dialect it cannot translate.
    auto isIdr = [](NamedAttribute attr) { return attr.getName().strref().starts_with("idr."); };
    module->setDiscardableAttrs(llvm::to_vector(llvm::make_filter_range(
        module->getDiscardableAttrs(), [&](NamedAttribute a) { return !isIdr(a); })));
    // So have those of the functions (their facts and a clone's key), and
    // the marks of their parameters.
    module.walk([&](Operation *op) {
      if (op == module.getOperation())
        return;
      for (NamedAttribute attr : llvm::to_vector(op->getDiscardableAttrs()))
        if (isIdr(attr))
          op->removeDiscardableAttr(attr.getName());
    });
    // In JIT mode closures call functions through pointers, and no call in
    // sight shows what they pass; the facts are the executable's.
    if (!jit) {
      facts.apply(*layouts);
      emitMain(module, root, io, runtime);
    }
  }
};

} // namespace
