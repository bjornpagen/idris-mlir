// idr-lower: idr to func, arith, scf, ub and llvm (docs/architecture/10-lowering.md).
// The layouts, runtime helpers and patterns it uses are in Lower/.

#include "Lower/Patterns.h"

#include "mlir/Dialect/ControlFlow/Transforms/StructuralTypeConversions.h"
#include "mlir/Dialect/Func/Transforms/FuncConversions.h"
#include "mlir/Dialect/SCF/Transforms/Patterns.h"

using namespace mlir;

namespace idr {
#define GEN_PASS_DEF_IDRLOWER
#include "idr/Passes.h.inc"
} // namespace idr

namespace {

struct Lower : idr::impl::IdrLowerBase<Lower> {
  void runOnOperation() override {
    ModuleOp module = getOperation();
    MLIRContext *ctx = &getContext();
    auto entry = module->getAttrOfType<FlatSymbolRefAttr>("idr.entry");
    auto kind = module->getAttrOfType<StringAttr>("idr.entry_kind");
    if (!entry || !kind) {
      module.emitError("internal error: idr-lower needs idr.entry and idr.entry_kind");
      return signalPassFailure();
    }

    idr::lower::Layouts layouts(module);
    idr::lower::Runtime runtime(module);
    idr::lower::Context state{layouts, runtime};

    // Static data and helpers are added before the conversion starts.
    bool ok = true;
    auto need = [&](StringRef name) { ok &= succeeded(runtime.require(name)); };
    module.walk([&](Operation *op) {
      if (auto lit = dyn_cast<idr::StrLitOp>(op))
        runtime.declareString(lit.getValue());
      else if (isa<idr::DivOp, idr::ModOp>(op) && !idr::lower::divisorKnownNonZero(op->getOperand(1))) {
        runtime.declareString(idr::lower::crashMessage(op->getLoc(), "division by zero"));
        need("__idr_crash");
      } else if (auto cast = dyn_cast<idr::ToIntOp>(op)) {
        if (!idr::lower::knownFinite(cast.getValue())) {
          runtime.declareString(
              idr::lower::crashMessage(op->getLoc(), "cast of a non-finite Double"));
          need("__idr_crash");
        }
        need("__idr_f64_to_i64");
      } else if (auto crash = dyn_cast<idr::CrashOp>(op)) {
        runtime.declareString(idr::lower::crashMessage(op->getLoc(), crash.getMessage()));
        need("__idr_crash");
      } else if (isa<idr::DoubleHeadOp>(op))
        need("__idr_double_head");
      else if (isa<idr::PutDoubleOp>(op))
        need("__idr_put_double");
      else if (isa<idr::PutStrOp>(op))
        need("__idr_put_bytes");
      else if (isa<idr::PutCharOp>(op))
        need("__idr_put_char");
      else if (auto put = dyn_cast<idr::PutIntOp>(op))
        need(put.getIsSigned() ? "__idr_put_int_s" : "__idr_put_int_u");
      else if (isa<idr::GetCharOp>(op))
        need("__idr_get_char");
      else if (isa<idr::GetByteOp>(op))
        need("__idr_get_byte");
      else if (isa<idr::ExitOp>(op))
        need("__idr_exit");
    });
    if (kind.getValue() == "io")
      need("__idr_flush");
    if (!ok)
      return signalPassFailure();

    TypeConverter converter;
    converter.addConversion([](Type type) { return type; });
    converter.addConversion([&](Type type, SmallVectorImpl<Type> &out)
                                -> std::optional<LogicalResult> {
      if (!isa<idr::ErasedType, idr::WorldType, idr::StrType, idr::DataType>(type))
        return std::nullopt;
      auto parts = layouts.components(type);
      out.append(parts.begin(), parts.end());
      return success();
    });

    ConversionTarget target(*ctx);
    target.addIllegalDialect<idr::IdrDialect>();
    target.addLegalDialect<arith::ArithDialect, math::MathDialect, LLVM::LLVMDialect,
                           cf::ControlFlowDialect>();
    target.addDynamicallyLegalOp<ub::PoisonOp>(
        [&](ub::PoisonOp op) { return converter.isLegal(op.getType()); });
    target.addDynamicallyLegalOp<arith::SelectOp>(
        [&](arith::SelectOp op) { return converter.isLegal(op.getType()); });
    // The blocks after the entry are converted with the branches to them.
    target.addDynamicallyLegalOp<func::FuncOp>([&](func::FuncOp op) {
      return converter.isSignatureLegal(op.getFunctionType()) &&
             (op.getBody().empty() || converter.isLegal(op.getBody().front().getArgumentTypes()));
    });
    target.addDynamicallyLegalOp<func::CallOp, func::ReturnOp>(
        [&](Operation *op) { return converter.isLegal(op); });
    // idr.data declarations are erased after the conversion (LOW-DATA-3).
    target.addLegalOp<idr::DataOp, idr::CtorOp>();

    RewritePatternSet patterns(ctx);
    populateFunctionOpInterfaceTypeConversionPattern<func::FuncOp>(patterns, converter);
    populateCallOpTypeConversionPattern(patterns, converter);
    populateReturnOpTypeConversionPattern(patterns, converter);
    scf::populateSCFStructuralTypeConversionsAndLegality(converter, patterns, target);
    cf::populateCFStructuralTypeConversionsAndLegality(converter, patterns, target);
    idr::lower::populatePatterns(patterns, converter, state);

    if (failed(applyPartialConversion(module, target, std::move(patterns))))
      return signalPassFailure();

    for (auto data : llvm::make_early_inc_range(module.getOps<idr::DataOp>()))
      data.erase();

    // LOW-ENTRY-1
    auto root = module.lookupSymbol<func::FuncOp>(entry.getAttr());
    if (!root || module.lookupSymbol("main")) {
      module.emitError("internal error: bad entry for idr-lower");
      return signalPassFailure();
    }
    OpBuilder b(ctx);
    b.setInsertionPointToEnd(module.getBody());
    Location loc = root.getLoc();
    root.setPrivate();
    auto main = func::FuncOp::create(b, loc, "main", b.getFunctionType({}, {b.getI32Type()}));
    b.setInsertionPointToStart(main.addEntryBlock());
    auto call = func::CallOp::create(b, loc, root, ValueRange{});
    Value status;
    if (kind.getValue() == "int") {
      status = arith::TruncIOp::create(b, loc, b.getI32Type(), call.getResult(0));
    } else {
      func::CallOp::create(b, loc, "__idr_flush", TypeRange{}, ValueRange{});
      status = arith::ConstantOp::create(b, loc, b.getI32IntegerAttr(0));
    }
    func::ReturnOp::create(b, loc, status);
    // The idr attributes have served their purpose; LLVM lowering would warn.
    module.walk([](func::FuncOp fn) {
      fn->removeAttr("idr.name");
      for (unsigned i = 0; i < fn.getNumArguments(); ++i)
        fn.removeArgAttr(i, "idr.quantity");
    });
    module->removeAttr("idr.version");
    module->removeAttr("idr.entry");
    module->removeAttr("idr.entry_kind");
  }
};


} // namespace
