// idr.lower:lowering: idr-lower, which takes idr to func, arith, math, scf,
// ub and llvm: phase 1 (matches and loops over arrays, on idr types), then
// phase 2, the conversion of every idr op and type, then the facts at
// function boundaries.
export module idr.lower:lowering;

import idr.mlir;
import idr.dialect;
import idr.layout;

import :arrayView;
import :closures;
import :facts;
import :fields;
import :loops;
import :matches;
import :patterns;
import :runtime;

using namespace mlir;

namespace idr::lower {

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

} // namespace

// idr-lower on `module`, a program or the calls of a round of compile-time
// evaluation alike: what differs between the two is a pass of its own after
// this one, idr-entry for a program and idr-meter for evaluation.
export LogicalResult lowerModule(ModuleOp module) {
  MLIRContext *ctx = module.getContext();
  if (failed(checkNoClosures(module)))
    return failure();
  FailureOr<layout::Layouts> layouts = layout::Layouts::of(module);
  if (failed(layouts))
    return failure();
  Runtime runtime(module, *layouts);
  Facts facts(module);
  // The parameters' idr attributes have served their purpose; the lowered
  // parameters get LLVM's instead (:facts).
  module.walk([](func::FuncOp fn) { fn.removeArgAttrsAttr(); });
  lowerMatches(module);
  lowerArrayLoops(module);
  // Read from the ops as the conversion will meet them.
  Fields fields(module);

  TypeConverter converter;
  converter.addConversion([](Type type) { return type; });
  converter.addConversion(
      [&](Type type, SmallVectorImpl<Type> &out) -> std::optional<LogicalResult> {
        if (type.getDialect().getNamespace() != IdrDialect::getDialectNamespace() &&
            !isArray(type))
          return std::nullopt;
        llvm::append_range(out, layouts->components(type));
        return success();
      });
  // A legal op that still holds an array of words (a linalg op over it,
  // :loops) gets the array's view of its cell and sizes (:arrayView).
  converter.addSourceMaterialization(
      [&](OpBuilder &b, Type type, ValueRange inputs, Location loc) -> Value {
        if (!isArray(type) || inputs.size() != layouts->components(type).size())
          return nullptr;
        return arrayView(b, loc, runtime, cast<MemRefType>(type), inputs);
      });

  ConversionTarget target(*ctx);
  target.addIllegalDialect<IdrDialect>();
  target.addLegalDialect<arith::ArithDialect, math::MathDialect, LLVM::LLVMDialect,
                         cf::ControlFlowDialect, memref::MemRefDialect, linalg::LinalgDialect>();
  // The one memref op of the contract, an array's length, becomes the
  // length beside the cell; the loads and stores the lowering itself makes
  // on an array's view stay for convert-to-llvm (:arrays).
  target.addIllegalOp<memref::DimOp>();
  target.addLegalOp<UnrealizedConversionCastOp, ub::UnreachableOp, func::CallIndirectOp,
                    func::ConstantOp>();
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
  populatePatterns(patterns, converter, *layouts, runtime, fields);
  populateLazyPatterns(patterns, converter, *layouts, runtime);

  ConversionConfig config;
  config.allowPatternRollback = false;
  if (failed(applyPartialConversion(module, target, std::move(patterns), config)))
    return failure();

  runtime.finish();
  for (auto data : llvm::make_early_inc_range(module.getOps<DataOp>()))
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
  facts.apply(*layouts);
  return success();
}

} // namespace idr::lower
