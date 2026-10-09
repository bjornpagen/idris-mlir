// idr.lower:lowering: idr-lower, which takes idr to func, arith, math, scf,
// ub and llvm: phase 1 (matches and loops over arrays, on idr types), then
// phase 2, the conversion of every idr op and type, then the facts at
// function boundaries and the program's entry.
module;
// The target entry's list of CPU features, an X-macro, and the runtime's
// C ABI, whose feature bits it names.
#include "cpu_features.h"
#include "idris_rt.h"

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
// enables, found by their LLVM names. A module with no target states no
// requirement.
uint64_t requiredCpuFeatures(ModuleOp module) {
  auto target = module->getAttrOfType<LLVM::TargetAttr>(LLVM::LLVMDialect::getTargetAttrName());
  LLVM::TargetFeaturesAttr features = target ? target.getFeatures() : nullptr;
  uint64_t bits = 0;
  if (!features)
    return bits;
#define IDR_REQUIRED_FEATURE(bit, test, name)                                                   \
  if (features.contains("+" name))                                                             \
    bits |= uint64_t{1} << (bit);
  IDRIS_RT_CPU_FEATURES(IDR_REQUIRED_FEATURE)
#undef IDR_REQUIRED_FEATURE
  return bits;
}

void emitMain(ModuleOp module, func::FuncOp root, bool io, Runtime &runtime) {
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

// A function closure left in a constant. A suspension is a ClosureAttr at
// !idr.lazy, and it stays: the cell is the value.
bool functionClosure(Attribute value, Type type, SymbolTable &symbols,
                     llvm::DenseSet<std::pair<Attribute, Type>> &seen) {
  type = unrestricted(type);
  if (!seen.insert({value, type}).second)
    return false;
  if (auto closure = dyn_cast<ClosureAttr>(value)) {
    if (!isa<LazyType>(type))
      return true;
    auto fn = symbols.lookup<func::FuncOp>(closure.getCallee().getAttr());
    if (!fn)
      return true;
    for (auto [capture, arg] : llvm::zip(closure.getCaptures(), fn.getArgumentTypes()))
      if (functionClosure(capture, arg, symbols, seen))
        return true;
    return false;
  }
  auto con = dyn_cast<ConAttr>(value);
  if (!con)
    return false;
  auto data = symbols.lookup<DataOp>(con.getCtor().getRootReference());
  auto ctor = data ? data.lookupSymbol<CtorOp>(con.getCtor().getLeafReference()) : CtorOp();
  if (!ctor)
    return true;
  for (auto [field, fieldType] :
       llvm::zip(con.getFields(), ctor.getFieldTypes().getAsValueRange<TypeAttr>()))
    if (functionClosure(field, fieldType, symbols, seen))
      return true;
  return false;
}

// idr-defunctionalize has made every closure of the program a sum: only
// idr-eval lowers code that still builds, applies or holds a closure.
// A suspension is not one.
LogicalResult checkNoClosures(ModuleOp module) {
  SymbolTable symbols(module);
  llvm::DenseSet<std::pair<Attribute, Type>> seen;
  WalkResult result = module.walk([&](Operation *op) {
    bool closure = isa<ClosureOp, ApplyOp>(op);
    if (auto constant = dyn_cast<ConstantOp>(op))
      closure = functionClosure(constant.getValue(), constant.getType(), symbols, seen);
    if (!closure)
      return WalkResult::advance();
    op->emitError("internal error: idr-lower: a closure is left after idr-defunctionalize");
    return WalkResult::interrupt();
  });
  return failure(result.wasInterrupted());
}

} // namespace

// idr-lower on `module`: for an executable, its root becomes the program's
// entry; in JIT mode (`jit`), for compile-time evaluation, every function
// counts a tick of the evaluator's meter when entered, and closures stay
// closures.
export LogicalResult lowerModule(ModuleOp module, bool jit) {
  MLIRContext *ctx = module.getContext();
  func::FuncOp root;
  bool io = false;
  if (!jit) {
    FailureOr<func::FuncOp> found = findRoot(module);
    if (failed(found))
      return failure();
    root = *found;
    io = llvm::any_of(root.getArgumentTypes(), isWorld);
    FunctionType kind = root.getFunctionType();
    if (!io && (kind.getNumInputs() != 0 || kind.getNumResults() != 1 ||
                !kind.getResult(0).isInteger(64))) {
      root.emitError("internal error: idr-lower: the root neither takes the world nor is "
                     "`() -> i64`");
      return failure();
    }
    if (failed(checkNoClosures(module)))
      return failure();
  }
  // Every evaluation is metered, total code with a larger budget, so every
  // function counts a tick when entered. idr-eval runs before idr-tail-loops
  // makes loops; a loop of code that need not end ticks at its
  // idr.may_loop.
  if (jit)
    for (auto fn : module.getOps<func::FuncOp>())
      if (!fn.isExternal()) {
        auto b = OpBuilder::atBlockBegin(&fn.getBody().front());
        MayLoopOp::create(b, fn.getLoc());
      }
  FailureOr<layout::Layouts> layouts = layout::Layouts::of(module);
  if (failed(layouts))
    return failure();
  Runtime runtime(module, *layouts, jit);
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
  // :loops) gets the array's view of its cell and length (:arrayView).
  converter.addSourceMaterialization(
      [&](OpBuilder &b, Type type, ValueRange inputs, Location loc) -> Value {
        if (!isArray(type) || inputs.size() != 2)
          return nullptr;
        return arrayView(b, loc, runtime, cast<MemRefType>(type), inputs[0], inputs[1]);
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
  if (jit)
    populateClosurePatterns(patterns, converter, *layouts, runtime);
  populateLazyPatterns(patterns, converter, *layouts, runtime);

  ConversionConfig config;
  config.allowPatternRollback = false;
  if (failed(applyPartialConversion(module, target, std::move(patterns), config)))
    return failure();

  runtime.emitCode();
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
  // In JIT mode closures call functions through pointers, and no call in
  // sight shows what they pass; the facts are the executable's.
  if (!jit) {
    facts.apply(*layouts);
    emitMain(module, root, io, runtime);
  }
  return success();
}

} // namespace idr::lower
