// idr-lower: idr to func, arith, math, scf, ub and llvm. The layouts,
// runtime calls, static data and patterns it uses are in Lower/.

#include "Lower/Patterns.h"

#include "mlir/Dialect/Func/Transforms/FuncConversions.h"
#include "mlir/Dialect/SCF/Transforms/Patterns.h"

using namespace mlir;

namespace idr {
#define GEN_PASS_DEF_IDRLOWER
#include "idr/Passes.h.inc"
} // namespace idr

namespace {

// The root, the only public function, becomes private, and
// @main runs it. Its type is its kind: `() -> i64` returns the exit status
// (its low 8 bits); an IO root takes the world, and main then writes
// pending output and returns 0.
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

void emitMain(ModuleOp module, func::FuncOp root, bool io, idr::lower::Runtime &runtime) {
  root.setPrivate();
  OpBuilder b(module.getContext());
  b.setInsertionPointToEnd(module.getBody());
  Location loc = root.getLoc();
  auto main = func::FuncOp::create(b, loc, "main", b.getFunctionType({}, {b.getI32Type()}));
  b.setInsertionPointToStart(main.addEntryBlock());
  auto call = func::CallOp::create(b, loc, root, ValueRange{});
  Value status;
  if (io) {
    runtime.call(b, loc, "idris_rt_flush", Type(), ValueRange{});
    status = arith::ConstantOp::create(b, loc, b.getI32IntegerAttr(0));
  } else {
    status = arith::TruncIOp::create(b, loc, b.getI32Type(), call.getResult(0));
  }
  func::ReturnOp::create(b, loc, status);
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
      io = llvm::any_of(root.getArgumentTypes(), llvm::IsaPred<idr::WorldType>);
    }
    idr::lower::Layouts layouts(module);
    idr::lower::Runtime runtime(module, layouts, jit);
    idr::lower::lowerMatches(module);

    TypeConverter converter;
    converter.addConversion([](Type type) { return type; });
    converter.addConversion(
        [&](Type type, SmallVectorImpl<Type> &out) -> std::optional<LogicalResult> {
          if (type.getDialect().getNamespace() != idr::IdrDialect::getDialectNamespace())
            return std::nullopt;
          llvm::append_range(out, layouts.components(type));
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
    idr::lower::populatePatterns(patterns, converter, layouts, runtime);

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
    // Calls carry idr-specialize's own (idr.spec_caller, idr.spec_stopped)
    // too, which the verifier accepts only on func.call.
    module.walk([&](Operation *op) {
      if (op == module.getOperation())
        return;
      for (NamedAttribute attr : llvm::to_vector(op->getDiscardableAttrs()))
        if (isIdr(attr))
          op->removeDiscardableAttr(attr.getName());
    });
    module.walk([&](func::FuncOp fn) {
      for (unsigned i = 0; i < fn.getNumArguments(); ++i)
        if (DictionaryAttr attrs = fn.getArgAttrDict(i))
          for (NamedAttribute attr : llvm::to_vector(attrs))
            if (isIdr(attr))
              fn.removeArgAttr(i, attr.getName());
    });
    if (!jit)
      emitMain(module, root, io, runtime);
  }
};

} // namespace
