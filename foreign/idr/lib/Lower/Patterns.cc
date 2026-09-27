// The conversion patterns of idr-lower: one per idr op.

#include "Lower/Patterns.h"

using namespace mlir;

namespace idr::lower {

namespace {

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

// LOW-TAIL-4: llvm.sideeffect, which LLVM keeps so that a loop that may not
// terminate is never deleted.
struct LowerMayLoop : IdrPattern<idr::MayLoopOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(idr::MayLoopOp op, OneToNOpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    LLVM::CallIntrinsicOp::create(rewriter, op.getLoc(),
                                  rewriter.getStringAttr("llvm.sideeffect"), ValueRange{});
    rewriter.eraseOp(op);
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

// A select of an idr value (canonicalize makes one from an scf.if) selects
// each of its components.
struct LowerSelect : IdrPattern<arith::SelectOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(arith::SelectOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Value cond = adaptor.getCondition().front();
    SmallVector<Value> out;
    for (auto [a, b] : llvm::zip_equal(adaptor.getTrueValue(), adaptor.getFalseValue()))
      out.push_back(arith::SelectOp::create(rewriter, op.getLoc(), cond, a, b));
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

// LOW-DBL-1: crash unless finite, then truncate and wrap in 64 bits, then to
// the result width.
struct LowerToInt : IdrPattern<idr::ToIntOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(idr::ToIntOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    Value x = adaptor.getValue();
    if (!knownFinite(op.getValue())) {
      Value finite = math::IsFiniteOp::create(rewriter, loc, x);
      Value bad = arith::XOrIOp::create(
          rewriter, loc, finite, arith::ConstantOp::create(rewriter, loc, rewriter.getBoolAttr(true)));
      auto check = scf::IfOp::create(rewriter, loc, bad, /*withElse=*/false);
      OpBuilder::InsertionGuard guard(rewriter);
      rewriter.setInsertionPointToStart(check.thenBlock());
      emitCrash(rewriter, loc, state.runtime, "cast of a non-finite Double");
    }
    auto i64 = rewriter.getI64Type();
    Value wide = func::CallOp::create(rewriter, loc, "__idr_f64_to_i64", i64, x).getResult(0);
    if (op.getType() == i64)
      rewriter.replaceOp(op, wide);
    else
      rewriter.replaceOpWithNewOp<arith::TruncIOp>(op, op.getType(), wide);
    return success();
  }
};

// LOW-CRASH-2: a missing case calls the crash helper; the code after it is
// unreachable.
struct LowerCrash : IdrPattern<idr::CrashOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(idr::CrashOp op, OneToNOpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    emitCrash(rewriter, op.getLoc(), state.runtime, op.getMessage());
    SmallVector<Type> types;
    if (failed(getTypeConverter()->convertType(op.getType(), types)))
      return failure();
    SmallVector<Value> poison;
    for (Type type : types)
      poison.push_back(ub::PoisonOp::create(rewriter, op.getLoc(), type));
    rewriter.replaceOpWithMultiple(op, {poison});
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
    } else if constexpr (std::is_same_v<OpT, idr::PutDoubleOp>) {
      if (failed(call("__idr_put_double", {}, adaptor.getValue())))
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

} // namespace

void populatePatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                      Context &state) {
  patterns.add<LowerCon, LowerTag, LowerField, LowerErased, LowerPoison, LowerSelect, LowerStr, LowerMayLoop,
               LowerToChar, LowerToInt, LowerCrash, LowerDivision<idr::DivOp, true>, LowerDivision<idr::ModOp, false>,
               LowerIO<idr::PutStrOp>, LowerIO<idr::PutCharOp>, LowerIO<idr::PutIntOp>, LowerIO<idr::PutDoubleOp>,
               LowerIO<idr::GetCharOp>, LowerIO<idr::ExitOp>>(converter, patterns.getContext(),
                                                              state);
}

} // namespace idr::lower
