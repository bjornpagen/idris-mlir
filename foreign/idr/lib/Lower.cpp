// idr-lower: idr to func, arith, scf, ub and llvm (docs/architecture/10-lowering.md).

#include "idr/Idr.h"

#include "mlir/Dialect/Func/Transforms/FuncConversions.h"
#include "mlir/Dialect/SCF/Transforms/Patterns.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/Parser/Parser.h"
#include "mlir/Transforms/DialectConversion.h"
#include "llvm/ADT/StringMap.h"

using namespace mlir;

namespace idr {
#define GEN_PASS_DEF_IDRLOWER
#include "idr/Passes.h.inc"
} // namespace idr

namespace {

//===----------------------------------------------------------------------===//
// Data layout (LOW-DATA-1)
//===----------------------------------------------------------------------===//

struct Layout {
  Type tag;                       // null when the type has at most one constructor
  SmallVector<Type> slots;
  // For each constructor name: for each field, the slots of its components.
  llvm::StringMap<SmallVector<SmallVector<unsigned>>> fields;

  SmallVector<Type> types() const {
    SmallVector<Type> all;
    if (tag)
      all.push_back(tag);
    all.append(slots.begin(), slots.end());
    return all;
  }
  unsigned offset() const { return tag ? 1 : 0; }
};

class Layouts {
public:
  Layouts(ModuleOp m) : module(m) {}

  const Layout &get(StringAttr name) {
    auto it = cache.find(name);
    if (it != cache.end())
      return it->second;
    auto data = module.lookupSymbol<idr::DataOp>(name);
    Layout layout;
    auto ctors = data.getCtors();
    Builder b(module.getContext());
    if (ctors.size() >= 2) {
      unsigned width = ctors.size() <= 256 ? 8u : ctors.size() <= 65536 ? 16u : 32u;
      layout.tag = b.getIntegerType(width);
    }
    for (idr::CtorOp ctor : ctors) {
      SmallVector<bool> used(layout.slots.size(), false);
      SmallVector<SmallVector<unsigned>> perField;
      for (Attribute field : ctor.getFieldTypes()) {
        SmallVector<unsigned> slots;
        for (Type component : components(cast<TypeAttr>(field).getValue())) {
          auto chosen = static_cast<unsigned>(layout.slots.size());
          for (unsigned i = 0; i < layout.slots.size(); ++i)
            if (!used[i] && layout.slots[i] == component) {
              chosen = i;
              break;
            }
          if (chosen == layout.slots.size()) {
            layout.slots.push_back(component);
            used.push_back(false);
          }
          used[chosen] = true;
          slots.push_back(chosen);
        }
        perField.push_back(std::move(slots));
      }
      layout.fields[ctor.getSymName()] = std::move(perField);
    }
    return cache.try_emplace(name, std::move(layout)).first->second;
  }

  // The runtime components of a field or value type.
  SmallVector<Type> components(Type type) {
    Builder b(module.getContext());
    if (isa<idr::ErasedType, idr::WorldType>(type))
      return {};
    if (isa<idr::StrType>(type))
      return {LLVM::LLVMPointerType::get(module.getContext()), b.getI64Type()};
    if (auto data = dyn_cast<idr::DataType>(type))
      return get(data.getName().getAttr()).types();
    return {type};
  }

private:
  ModuleOp module;
  DenseMap<StringAttr, Layout> cache;
};

//===----------------------------------------------------------------------===//
// Runtime helpers and static data
//===----------------------------------------------------------------------===//

constexpr const char *runtimeSource =
#include "Runtime.mlir.inc"
    ;

class Runtime {
public:
  Runtime(ModuleOp m) : module(m) {}

  // Copies helper `name` and everything it references into the module.
  LogicalResult require(StringRef name) {
    if (!helpers) {
      helpers = parseSourceString<ModuleOp>(runtimeSource, module.getContext());
      if (!helpers)
        return module.emitError("internal error: idr runtime helpers do not parse");
    }
    SmallVector<StringRef> work{name};
    while (!work.empty()) {
      StringRef next = work.pop_back_val();
      if (module.lookupSymbol(next))
        continue;
      Operation *op = helpers->lookupSymbol(next);
      if (!op)
        return module.emitError("internal error: missing idr helper ") << next;
      OpBuilder b(module.getBodyRegion());
      b.setInsertionPointToEnd(module.getBody());
      b.clone(*op);
      op->walk([&](Operation *inner) {
        for (NamedAttribute attr : inner->getAttrs())
          attr.getValue().walk([&](FlatSymbolRefAttr ref) {
            work.push_back(ref.getValue());
          });
      });
    }
    return success();
  }

  // Declares the static data for `bytes` (LOW-STR-1). Called before the
  // conversion starts, so patterns only reference existing globals.
  void declareString(StringRef bytes) {
    if (bytes.empty() || strings.count(bytes))
      return;
    std::string name = ("__idr_str_" + Twine(strings.size())).str();
    strings[bytes] = name;
    OpBuilder b(module.getBodyRegion());
    b.setInsertionPointToStart(module.getBody());
    auto arrayType = LLVM::LLVMArrayType::get(b.getI8Type(), bytes.size());
    LLVM::GlobalOp::create(b, module.getLoc(), arrayType, /*isConstant=*/true,
                           LLVM::Linkage::Internal, name, b.getStringAttr(bytes),
                           /*alignment=*/0);
  }

  // The address and byte length of a declared static string.
  std::pair<Value, Value> string(OpBuilder &b, Location loc, StringRef bytes) const {
    auto ptrType = LLVM::LLVMPointerType::get(b.getContext());
    Value len = arith::ConstantOp::create(
        b, loc, b.getI64IntegerAttr(static_cast<int64_t>(bytes.size())));
    if (bytes.empty())
      return {LLVM::ZeroOp::create(b, loc, ptrType), len};
    Value addr = LLVM::AddressOfOp::create(b, loc, ptrType, strings.lookup(bytes));
    return {addr, len};
  }

private:
  ModuleOp module;
  OwningOpRef<ModuleOp> helpers;
  llvm::StringMap<std::string> strings;
};

std::string describe(Location loc) {
  if (auto file = dyn_cast<FileLineColLoc>(loc))
    return (file.getFilename().getValue() + ":" + Twine(file.getLine()) + ":" +
            Twine(file.getColumn()))
        .str();
  if (auto fused = dyn_cast<FusedLoc>(loc))
    for (Location inner : fused.getLocations())
      if (auto text = describe(inner); !text.empty())
        return text;
  if (auto named = dyn_cast<NameLoc>(loc))
    return describe(named.getChildLoc());
  if (auto site = dyn_cast<CallSiteLoc>(loc))
    return describe(site.getCallee());
  return "";
}

std::string crashMessage(Location loc, StringRef cause) {
  std::string where = describe(loc);
  return ("idris-mlir: " + cause + (where.empty() ? "" : " at " + where) + "\n").str();
}

bool divisorKnownNonZero(Value divisor) {
  APInt known;
  return matchPattern(divisor, m_ConstantInt(&known)) && !known.isZero();
}

// Calls @__idr_crash with a message naming the cause and the Idris location.
void emitCrash(OpBuilder &b, Location loc, const Runtime &runtime, StringRef cause) {
  auto [ptr, len] = runtime.string(b, loc, crashMessage(loc, cause));
  func::CallOp::create(b, loc, "__idr_crash", TypeRange{}, ValueRange{ptr, len});
}

//===----------------------------------------------------------------------===//
// Conversion patterns
//===----------------------------------------------------------------------===//

struct Context {
  Layouts &layouts;
  const Runtime &runtime;
};

template <typename OpT>
struct IdrPattern : OpConversionPattern<OpT> {
  IdrPattern(const TypeConverter &converter, MLIRContext *ctx, Context &s)
      : OpConversionPattern<OpT>(converter, ctx), state(s) {}
  Context &state;
};

struct LowerCon : IdrPattern<idr::ConOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(idr::ConOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    auto type = cast<idr::DataType>(op.getResult().getType());
    const Layout &layout = state.layouts.get(type.getName().getAttr());
    auto data = rewriter.getInsertionBlock()->getParentOp()->getParentOfType<ModuleOp>()
                    .lookupSymbol<idr::DataOp>(type.getName().getAttr());
    idr::CtorOp ctor = idr::lookupCtor(data, op.getCtor().getLeafReference());
    Location loc = op.getLoc();
    SmallVector<Value> slots(layout.slots.size());
    const auto &fields = layout.fields.find(ctor.getSymName())->second;
    for (auto [field, values] : llvm::zip(fields, adaptor.getFields()))
      for (auto [slot, value] : llvm::zip(field, values))
        slots[slot] = value;
    SmallVector<Value> out;
    if (layout.tag)
      out.push_back(arith::ConstantOp::create(
          rewriter, loc, IntegerAttr::get(layout.tag, static_cast<int64_t>(ctor.getTag()))));
    for (auto [slot, value] : llvm::enumerate(slots))
      out.push_back(value ? value
                          : ub::PoisonOp::create(rewriter, loc, layout.slots[slot])
                                .getResult());
    rewriter.replaceOpWithMultiple(op, {out});
    return success();
  }
};

struct LowerTag : IdrPattern<idr::TagOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(idr::TagOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    auto type = cast<idr::DataType>(op.getValue().getType());
    const Layout &layout = state.layouts.get(type.getName().getAttr());
    Value tag;
    if (layout.tag)
      tag = arith::IndexCastUIOp::create(rewriter, op.getLoc(), rewriter.getIndexType(),
                                         adaptor.getValue().front());
    else
      tag = arith::ConstantIndexOp::create(rewriter, op.getLoc(), 0);
    rewriter.replaceOp(op, tag);
    return success();
  }
};

struct LowerField : IdrPattern<idr::FieldOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(idr::FieldOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    auto type = cast<idr::DataType>(op.getValue().getType());
    const Layout &layout = state.layouts.get(type.getName().getAttr());
    const auto &field =
        layout.fields.find(op.getCtor())->second[op.getIndex()];
    ValueRange values = adaptor.getValue();
    SmallVector<Value> out;
    for (unsigned slot : field)
      out.push_back(values[layout.offset() + slot]);
    rewriter.replaceOpWithMultiple(op, {out});
    return success();
  }
};

struct LowerErased : IdrPattern<idr::ErasedOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(idr::ErasedOp op, OneToNOpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOpWithMultiple(op, {ValueRange{}});
    return success();
  }
};

// Poison of an idr type (from idr-tail-loops) becomes poison of each component.
struct LowerPoison : IdrPattern<ub::PoisonOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(ub::PoisonOp op, OneToNOpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    SmallVector<Type> types;
    if (failed(getTypeConverter()->convertType(op.getType(), types)))
      return failure();
    SmallVector<Value> out;
    for (Type type : types)
      out.push_back(ub::PoisonOp::create(rewriter, op.getLoc(), type));
    rewriter.replaceOpWithMultiple(op, {out});
    return success();
  }
};

struct LowerStr : IdrPattern<idr::StrLitOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(idr::StrLitOp op, OneToNOpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    auto [ptr, len] = state.runtime.string(rewriter, op.getLoc(), op.getValue());
    rewriter.replaceOpWithMultiple(op, {{ptr, len}});
    return success();
  }
};

// LOW-DIV-1
template <typename OpT, bool Quotient>
struct LowerDivision : IdrPattern<OpT> {
  using IdrPattern<OpT>::IdrPattern;
  LogicalResult matchAndRewrite(OpT op, typename OpT::Adaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    Value a = adaptor.getLhs(), b = adaptor.getRhs();
    Type type = a.getType();
    unsigned width = type.getIntOrFloatBitWidth();
    auto constant = [&](const APInt &value) -> Value {
      return arith::ConstantOp::create(rewriter, loc, IntegerAttr::get(type, value));
    };
    Value zero = constant(APInt::getZero(width));
    Value one = constant(APInt(width, 1));
    bool nonZero = divisorKnownNonZero(op.getRhs());
    if (!nonZero) {
      Value isZero = arith::CmpIOp::create(rewriter, loc, arith::CmpIPredicate::eq, b, zero);
      auto check = scf::IfOp::create(rewriter, loc, isZero, /*withElse=*/false);
      OpBuilder::InsertionGuard guard(rewriter);
      rewriter.setInsertionPointToStart(check.thenBlock());
      emitCrash(rewriter, loc, this->state.runtime, "division by zero");
    }
    Value result;
    if (!op.getIsSigned()) {
      Value safe = nonZero ? b : arith::SelectOp::create(
                                     rewriter, loc,
                                     arith::CmpIOp::create(rewriter, loc,
                                                           arith::CmpIPredicate::eq, b, zero),
                                     one, b);
      result = Quotient ? Value(arith::DivUIOp::create(rewriter, loc, a, safe))
                        : Value(arith::RemUIOp::create(rewriter, loc, a, safe));
    } else {
      // MIN / -1 and division by zero (already crashed) use divisor 1, which
      // gives MIN and 0: exactly the wrapped Euclidean results (SEM-INT-3).
      Value min = constant(APInt::getSignedMinValue(width));
      Value minusOne = constant(APInt::getAllOnes(width));
      Value isMin = arith::CmpIOp::create(rewriter, loc, arith::CmpIPredicate::eq, a, min);
      Value isM1 = arith::CmpIOp::create(rewriter, loc, arith::CmpIPredicate::eq, b, minusOne);
      Value overflow = arith::AndIOp::create(rewriter, loc, isMin, isM1);
      Value isZero = arith::CmpIOp::create(rewriter, loc, arith::CmpIPredicate::eq, b, zero);
      Value bad = arith::OrIOp::create(rewriter, loc, overflow, isZero);
      Value d = arith::SelectOp::create(rewriter, loc, bad, one, b);
      Value q = arith::DivSIOp::create(rewriter, loc, a, d);
      Value r = arith::RemSIOp::create(rewriter, loc, a, d);
      Value negative = arith::CmpIOp::create(rewriter, loc, arith::CmpIPredicate::slt, r, zero);
      Value positive = arith::CmpIOp::create(rewriter, loc, arith::CmpIPredicate::sgt, d, zero);
      if (Quotient) {
        Value down = arith::SubIOp::create(rewriter, loc, q, one);
        Value up = arith::AddIOp::create(rewriter, loc, q, one);
        Value adjusted = arith::SelectOp::create(rewriter, loc, positive, down, up);
        result = arith::SelectOp::create(rewriter, loc, negative, adjusted, q);
      } else {
        Value plus = arith::AddIOp::create(rewriter, loc, r, d);
        Value minus = arith::SubIOp::create(rewriter, loc, r, d);
        Value adjusted = arith::SelectOp::create(rewriter, loc, positive, plus, minus);
        result = arith::SelectOp::create(rewriter, loc, negative, adjusted, r);
      }
    }
    rewriter.replaceOp(op, result);
    return success();
  }
};

// LOW-CHAR-1
struct LowerToChar : IdrPattern<idr::ToCharOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(idr::ToCharOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    Value x = adaptor.getValue();
    auto i64 = rewriter.getI64Type();
    auto width = x.getType().getIntOrFloatBitWidth();
    if (width < 64)
      x = op.getIsSigned() ? Value(arith::ExtSIOp::create(rewriter, loc, i64, x))
                         : Value(arith::ExtUIOp::create(rewriter, loc, i64, x));
    auto c = [&](int64_t v) -> Value {
      return arith::ConstantOp::create(rewriter, loc, rewriter.getI64IntegerAttr(v));
    };
    // Unsigned comparison treats negative signed values as huge: not scalar.
    auto ule = arith::CmpIPredicate::ule, uge = arith::CmpIPredicate::uge;
    Value low = arith::CmpIOp::create(rewriter, loc, ule, x, c(0xD7FF));
    Value hiA = arith::CmpIOp::create(rewriter, loc, uge, x, c(0xE000));
    Value hiB = arith::CmpIOp::create(rewriter, loc, ule, x, c(0x10FFFF));
    Value high = arith::AndIOp::create(rewriter, loc, hiA, hiB);
    Value scalar = arith::OrIOp::create(rewriter, loc, low, high);
    Value narrow = arith::TruncIOp::create(rewriter, loc, rewriter.getI32Type(), x);
    Value zero = arith::ConstantOp::create(rewriter, loc, rewriter.getI32IntegerAttr(0));
    rewriter.replaceOpWithNewOp<arith::SelectOp>(op, scalar, narrow, zero);
    return success();
  }
};

// LOW-IO-2: each IO op calls a helper; the world vanishes (LOW-IO-3).
template <typename OpT>
struct LowerIO : IdrPattern<OpT> {
  using IdrPattern<OpT>::IdrPattern;
  LogicalResult matchAndRewrite(OpT op, typename IdrPattern<OpT>::OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    auto call = [&](StringRef name, TypeRange results, ValueRange args) -> FailureOr<func::CallOp> {
      return func::CallOp::create(rewriter, loc, name, results, args);
    };
    if constexpr (std::is_same_v<OpT, idr::PutStrOp>) {
      if (failed(call("__idr_put_bytes", {}, adaptor.getStr())))
        return failure();
    } else if constexpr (std::is_same_v<OpT, idr::PutCharOp>) {
      if (failed(call("__idr_put_char", {}, adaptor.getCh())))
        return failure();
    } else if constexpr (std::is_same_v<OpT, idr::PutIntOp>) {
      Value v = adaptor.getValue().front();
      auto i64 = rewriter.getI64Type();
      if (v.getType() != i64)
        v = op.getIsSigned() ? Value(arith::ExtSIOp::create(rewriter, loc, i64, v))
                           : Value(arith::ExtUIOp::create(rewriter, loc, i64, v));
      if (failed(call(op.getIsSigned() ? "__idr_put_int_s" : "__idr_put_int_u", {}, v)))
        return failure();
    } else if constexpr (std::is_same_v<OpT, idr::GetCharOp>) {
      auto got = call("__idr_get_char", rewriter.getI32Type(), {});
      if (failed(got))
        return failure();
      rewriter.replaceOpWithMultiple(op, {ValueRange{got->getResult(0)}, ValueRange{}});
      return success();
    } else {
      static_assert(std::is_same_v<OpT, idr::ExitOp>);
      if (failed(call("__idr_exit", {}, adaptor.getCode())))
        return failure();
    }
    rewriter.replaceOpWithMultiple(op, {ValueRange{}});
    return success();
  }
};

//===----------------------------------------------------------------------===//
// The pass
//===----------------------------------------------------------------------===//

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

    Layouts layouts(module);
    Runtime runtime(module);
    Context state{layouts, runtime};

    // Static data and helpers are added before the conversion starts.
    bool ok = true;
    auto need = [&](StringRef name) { ok &= succeeded(runtime.require(name)); };
    module.walk([&](Operation *op) {
      if (auto lit = dyn_cast<idr::StrLitOp>(op))
        runtime.declareString(lit.getValue());
      else if (isa<idr::DivOp, idr::ModOp>(op) && !divisorKnownNonZero(op->getOperand(1))) {
        runtime.declareString(crashMessage(op->getLoc(), "division by zero"));
        need("__idr_crash");
      } else if (isa<idr::PutStrOp>(op))
        need("__idr_put_bytes");
      else if (isa<idr::PutCharOp>(op))
        need("__idr_put_char");
      else if (auto put = dyn_cast<idr::PutIntOp>(op))
        need(put.getIsSigned() ? "__idr_put_int_s" : "__idr_put_int_u");
      else if (isa<idr::GetCharOp>(op))
        need("__idr_get_char");
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
    target.addLegalDialect<arith::ArithDialect, LLVM::LLVMDialect, cf::ControlFlowDialect>();
    target.addDynamicallyLegalOp<ub::PoisonOp>(
        [&](ub::PoisonOp op) { return converter.isLegal(op.getType()); });
    target.addDynamicallyLegalOp<func::FuncOp>([&](func::FuncOp op) {
      return converter.isSignatureLegal(op.getFunctionType()) &&
             converter.isLegal(&op.getBody());
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
    patterns.add<LowerCon, LowerTag, LowerField, LowerErased, LowerPoison, LowerStr,
                 LowerToChar, LowerDivision<idr::DivOp, true>,
                 LowerDivision<idr::ModOp, false>, LowerIO<idr::PutStrOp>,
                 LowerIO<idr::PutCharOp>, LowerIO<idr::PutIntOp>,
                 LowerIO<idr::GetCharOp>, LowerIO<idr::ExitOp>>(converter, ctx, state);

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
