// Phase 2 of idr-lower: the conversion pattern of each idr op.

#include "Lower/Patterns.h"
#include "Stack/Cell.h"

#include "mlir/Dialect/Math/IR/Math.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::lower {

Value buildBox(OpBuilder &b, Location loc, Layouts &layouts, Runtime &runtime, CtorOp ctor,
               Value cell, ArrayRef<ValueRange> fields) {
  const Cell &layout = layouts.box(ctor);
  if (!cell)
    cell = runtime.allocate(b, loc, layout.size, layout.info);
  for (auto [slots, values] : llvm::zip_equal(layout.fields, fields))
    runtime.store(b, loc, cell, slots, values);
  return cell;
}

namespace {

SmallVector<Value> flatten(ArrayRef<ValueRange> operands) {
  SmallVector<Value> values;
  for (ValueRange operand : operands)
    llvm::append_range(values, operand);
  return values;
}

Value constantI64(OpBuilder &b, Location loc, int64_t value) {
  return arith::ConstantOp::create(b, loc, b.getI64IntegerAttr(value));
}

// An unboxed constructor is its tag and its components in their slots, an
// empty value in the counted slots it does not use and poison in the
// others. A boxed one is a new cell holding its tag and components.
struct LowerCon : IdrPattern<ConOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(ConOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    CtorOp ctor = lookupCtor(op, op.getCtor());
    if (isa<BoxType>(op.getType())) {
      // idr-stack: a cell that never outlives its frame is a slot of it.
      Value box = buildBox(rewriter, loc, layouts, runtime, ctor,
                           stack::cell(rewriter, loc, op, layouts, runtime), adaptor.getFields());
      rewriter.replaceOp(op, box);
      return success();
    }
    const SumLayout &layout = layouts.sum(cast<DataType>(op.getType()).getName().getAttr());
    SmallVector<Value> slots(layout.slots.size());
    const auto &fields = layout.fields.find(ctor.getSymName())->second;
    for (auto [field, values] : llvm::zip_equal(fields, adaptor.getFields()))
      for (auto [slot, value] : llvm::zip_equal(field, values))
        slots[slot] = value;
    SmallVector<Value> out;
    if (layout.tag)
      out.push_back(arith::ConstantOp::create(
          rewriter, loc, IntegerAttr::get(layout.tag, static_cast<int64_t>(ctor.getTag()))));
    for (auto [slot, value] : llvm::enumerate(slots))
      out.push_back(value                  ? value
                    : layout.counted[slot] ? runtime.null(rewriter, loc, layout.slots[slot])
                                           : ub::PoisonOp::create(rewriter, loc, layout.slots[slot])
                                                 .getResult());
    rewriter.replaceOpWithMultiple(op, {out});
    return success();
  }
};

// The tag slot, extended to i64, or 0 for one constructor; a
// box's tag is in its header.
struct LowerTag : IdrPattern<TagOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(TagOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    auto i64 = rewriter.getI64Type();
    if (isa<BoxType>(op.getValue().getType())) {
      Value tag = runtime.loadTag(rewriter, loc, adaptor.getValue().front());
      rewriter.replaceOpWithNewOp<arith::ExtUIOp>(op, i64, tag);
      return success();
    }
    const SumLayout &layout = layouts.sum(cast<DataType>(op.getValue().getType()).getName().getAttr());
    if (!layout.tag)
      rewriter.replaceOp(op, constantI64(rewriter, loc, 0));
    else
      rewriter.replaceOpWithNewOp<arith::ExtUIOp>(op, i64, adaptor.getValue().front());
    return success();
  }
};

// The components of a field from its constructor's slots, or
// loaded from a box's cell.
struct LowerField : IdrPattern<FieldOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(FieldOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    auto index = static_cast<unsigned>(op.getIndex());
    Type type = op.getValue().getType();
    if (isa<BoxType>(type)) {
      CtorOp ctor = lookupCtor(lookupData(op, type), op.getCtor());
      rewriter.replaceOpWithMultiple(
          op, {runtime.load(rewriter, op.getLoc(), adaptor.getValue().front(),
                            layouts.box(ctor).fields[index])});
      return success();
    }
    const SumLayout &layout = layouts.sum(cast<DataType>(type).getName().getAttr());
    ValueRange values = adaptor.getValue();
    SmallVector<Value> out;
    for (unsigned slot : layout.fields.find(op.getCtor())->second[index])
      out.push_back(values[layout.offset() + slot]);
    rewriter.replaceOpWithMultiple(op, {out});
    return success();
  }
};

// Strings, bigs, boxes and closures are static data; an unboxed
// constant is its components.
struct LowerConstant : IdrPattern<ConstantOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(ConstantOp op, OneToNOpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOpWithMultiple(
        op, {runtime.constant(rewriter, op.getLoc(), op.getValue(), op.getType())});
    return success();
  }
};

// Linearity has no runtime form: entering and using a linear value is the
// value itself. Nor has non-negativity: a natural is the Integer it is.
template <typename OpT>
struct LowerAsItself : IdrPattern<OpT> {
  using IdrPattern<OpT>::IdrPattern;
  LogicalResult matchAndRewrite(OpT op, typename IdrPattern<OpT>::OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    ValueRange value = adaptor.getOperands().front();
    rewriter.replaceOpWithMultiple(op, {SmallVector<Value>(value.begin(), value.end())});
    return success();
  }
};

// A pending field is stored as poison: it is written through its
// destination before anything reads it.
struct LowerPending : IdrPattern<PendingOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(PendingOp op, OneToNOpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    SmallVector<Value> out;
    for (Type type : layouts.components(op.getType()))
      out.push_back(ub::PoisonOp::create(rewriter, op.getLoc(), type));
    rewriter.replaceOpWithMultiple(op, {out});
    return success();
  }
};

// A destination is the address of its field's word in the cell.
struct LowerDestOf : IdrPattern<DestOfOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(DestOfOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    CtorOp ctor = lookupCtor(lookupData(op, op.getValue().getType()), op.getCtor());
    const auto &slots = layouts.box(ctor).fields[static_cast<unsigned>(op.getIndex())];
    rewriter.replaceOp(op, runtime.address(rewriter, op.getLoc(), adaptor.getValue().front(),
                                           slots.front()));
    return success();
  }
};

struct LowerDestWrite : IdrPattern<DestWriteOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(DestWriteOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    runtime.storeWord(rewriter, op.getLoc(), adaptor.getDest().front(),
                      adaptor.getValue().front());
    rewriter.eraseOp(op);
    return success();
  }
};

// The runtime's crash, which does not return; the
// ub.unreachable after it stays.
struct LowerCrash : IdrPattern<CrashOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(CrashOp op, OpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    runtime.crash(rewriter, op.getLoc(), op.getMessage());
    rewriter.eraseOp(op);
    return success();
  }
};

struct LowerMayLoop : IdrPattern<MayLoopOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(MayLoopOp op, OpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    runtime.mayLoop(rewriter, op.getLoc());
    rewriter.eraseOp(op);
    return success();
  }
};

// Poison of an idr type becomes poison of each component, but for the
// counted ones, which are empty: poison may still be dropped, as what a
// function nobody reads is passed, or what idr-tail-loops forwards on the
// path it does not take.
struct LowerPoison : IdrPattern<ub::PoisonOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(ub::PoisonOp op, OneToNOpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    SmallVector<Value> out;
    for (auto [type, isCounted] :
         llvm::zip_equal(layouts.components(op.getType()), layouts.counted(op.getType())))
      out.push_back(isCounted ? runtime.null(rewriter, op.getLoc(), type)
                              : ub::PoisonOp::create(rewriter, op.getLoc(), type).getResult());
    rewriter.replaceOpWithMultiple(op, {out});
    return success();
  }
};

// A select of an idr value selects each of its components.
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

template <typename OpT>
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
    auto cause = op.getCrashCause();
    if (cause)
      this->runtime.crashIf(
          rewriter, loc, arith::CmpIOp::create(rewriter, loc, arith::CmpIPredicate::eq, b, zero),
          *cause);
    Value result;
    if (!op.getIsSigned()) {
      Value safe = !cause ? b
                          : arith::SelectOp::create(
                                rewriter, loc,
                                arith::CmpIOp::create(rewriter, loc, arith::CmpIPredicate::eq, b, zero),
                                one, b);
      result = OpT::quotient ? Value(arith::DivUIOp::create(rewriter, loc, a, safe))
                             : Value(arith::RemUIOp::create(rewriter, loc, a, safe));
    } else {
      // MIN / -1 and division by zero (already crashed) use divisor 1, which
      // gives MIN and 0: exactly the wrapped Euclidean results.
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
      if constexpr (OpT::quotient) {
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

struct LowerToChar : IdrPattern<ToCharOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(ToCharOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    Value x = adaptor.getValue();
    auto i64 = rewriter.getI64Type();
    if (x.getType().getIntOrFloatBitWidth() < 64)
      x = op.getIsSigned() ? Value(arith::ExtSIOp::create(rewriter, loc, i64, x))
                           : Value(arith::ExtUIOp::create(rewriter, loc, i64, x));
    auto c = [&](int64_t v) { return constantI64(rewriter, loc, v); };
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

//===----------------------------------------------------------------------===//
// Runtime calls
//===----------------------------------------------------------------------===//

// The runtime function of an op is named after it (Idr_CallsRuntime). Where
// the op's signedness or operand type picks the function, the name ends in
// _s, _u or _f64 and an integer is extended to 64 bits as the signedness
// says. Ops whose result width varies get the result modulo 2^64 and
// truncate it.
template <typename OpT>
constexpr bool returnsWord = llvm::is_one_of<OpT, ToIntOp, StrToIntOp>::value;

// The ops whose small case is inline (Bigs.cc), which call the runtime only
// on their cold path.
template <typename OpT>
constexpr bool smallCaseInline = llvm::is_one_of<OpT, BigAddOp, BigSubOp, BigMulOp, BigPredOp,
                                                 BigCmpOp, NatFromBigOp, BigFromIntOp,
                                                 BigToIntOp>::value;

template <typename OpT>
std::optional<bool> signedness(OpT op) {
  if constexpr (requires { op.getIsSigned(); })
    return op.getIsSigned();
  return std::nullopt;
}

Value stringLength(OpBuilder &b, Location loc, Runtime &runtime, Value s) {
  return runtime.call(b, loc, "idris_rt_str_length", b.getI64Type(), s);
}

Value notFinite(OpBuilder &b, Location loc, Value x) {
  Value finite = math::IsFiniteOp::create(b, loc, x);
  Value yes = arith::ConstantOp::create(b, loc, b.getBoolAttr(true));
  return arith::XOrIOp::create(b, loc, finite, yes);
}

// Where the op crashes; checked before the call, whose runtime
// function assumes it does not.
Value crashCondition(StrIndexOp, OpBuilder &b, Location loc, Runtime &runtime,
                     ArrayRef<Value> args) {
  return arith::CmpIOp::create(b, loc, arith::CmpIPredicate::uge, args[1],
                               stringLength(b, loc, runtime, args[0]));
}
Value emptyString(OpBuilder &b, Location loc, Runtime &runtime, Value s) {
  return arith::CmpIOp::create(b, loc, arith::CmpIPredicate::eq, stringLength(b, loc, runtime, s),
                               constantI64(b, loc, 0));
}
Value crashCondition(StrHeadOp, OpBuilder &b, Location loc, Runtime &runtime,
                     ArrayRef<Value> args) {
  return emptyString(b, loc, runtime, args[0]);
}
Value crashCondition(StrTailOp, OpBuilder &b, Location loc, Runtime &runtime,
                     ArrayRef<Value> args) {
  return emptyString(b, loc, runtime, args[0]);
}
// Zero is the small word 1.
Value bigZero(OpBuilder &b, Location loc, Value big) {
  return arith::CmpIOp::create(b, loc, arith::CmpIPredicate::eq, big, constantI64(b, loc, 1));
}
Value crashCondition(BigDivOp, OpBuilder &b, Location loc, Runtime &, ArrayRef<Value> args) {
  return bigZero(b, loc, args[1]);
}
Value crashCondition(BigModOp, OpBuilder &b, Location loc, Runtime &, ArrayRef<Value> args) {
  return bigZero(b, loc, args[1]);
}
Value crashCondition(BigFromDoubleOp, OpBuilder &b, Location loc, Runtime &,
                     ArrayRef<Value> args) {
  return notFinite(b, loc, args[0]);
}
Value crashCondition(ToIntOp, OpBuilder &b, Location loc, Runtime &, ArrayRef<Value> args) {
  return notFinite(b, loc, args[0]);
}

// The range an op states for its result whatever its operands are, as
// LLVM's `range`: the runtime keeps the op's meaning, so the call's result
// is in it too. An op whose range depends on its operands states nothing
// here, since every operand is taken to be any value.
std::optional<LLVM::ConstantRangeAttr> statedRange(Operation *op) {
  auto ranged = dyn_cast<InferIntRangeInterface>(op);
  if (!ranged || op->getNumResults() != 1)
    return std::nullopt;
  auto operands = llvm::map_to_vector(op->getOperands(), [](Value operand) {
    return IntegerValueRange::getMaxRange(operand);
  });
  std::optional<ConstantIntRanges> stated;
  ranged.inferResultRangesFromOptional(operands, [&](Value, const IntegerValueRange &range) {
    if (!range.isUninitialized())
      stated = range.getValue();
  });
  // LLVM's range is half-open, so a range up to the type's largest value
  // is one LLVM cannot state, and says nothing worth stating.
  if (!stated || stated->umax().isMaxValue())
    return std::nullopt;
  return LLVM::ConstantRangeAttr::get(op->getContext(), stated->umin(), stated->umax() + 1);
}

template <typename OpT>
struct LowerRuntimeCall : IdrPattern<OpT> {
  using IdrPattern<OpT>::IdrPattern;
  LogicalResult matchAndRewrite(OpT op, typename IdrPattern<OpT>::OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    std::string name = op.getHelper().str();
    SmallVector<Value> args = flatten(adaptor.getOperands());
    if (std::optional<bool> isSigned = signedness(op)) {
      for (Value &arg : args) {
        if (isa<FloatType>(arg.getType())) {
          name += "_f64";
        } else if (auto integer = dyn_cast<IntegerType>(arg.getType())) {
          name += *isSigned ? "_s" : "_u";
          if (integer.getWidth() < 64)
            arg = *isSigned ? Value(arith::ExtSIOp::create(rewriter, loc, rewriter.getI64Type(), arg))
                            : Value(arith::ExtUIOp::create(rewriter, loc, rewriter.getI64Type(), arg));
        }
      }
    }
    if constexpr (requires { crashCondition(op, rewriter, loc, this->runtime, args); })
      if (std::optional<StringRef> cause = op.getCrashCause())
        this->runtime.crashIf(rewriter, loc, crashCondition(op, rewriter, loc, this->runtime, args),
                              *cause);
    SmallVector<Type> results;
    for (Type type : op->getResultTypes())
      llvm::append_range(results, this->layouts.components(type));
    Type result = results.empty() ? Type() : results.front();
    if constexpr (returnsWord<OpT>)
      result = rewriter.getI64Type();
    Value value = this->runtime.call(rewriter, loc, name, result, args);
    if constexpr (returnsWord<OpT>) {
      if (results.front() != value.getType())
        value = arith::TruncIOp::create(rewriter, loc, results.front(), value);
    } else if (std::optional<LLVM::ConstantRangeAttr> range = statedRange(op)) {
      auto call = value.getDefiningOp<LLVM::CallOp>();
      call.setResAttrsAttr(rewriter.getArrayAttr(rewriter.getDictionaryAttr(
          rewriter.getNamedAttr(LLVM::LLVMDialect::getRangeAttrName(), *range))));
    }
    SmallVector<SmallVector<Value>> out;
    for (Type type : op->getResultTypes())
      out.push_back(this->layouts.components(type).empty() ? SmallVector<Value>{}
                                                           : SmallVector<Value>{value});
    rewriter.replaceOpWithMultiple(op, std::move(out));
    return success();
  }
};

// str.cmp: the runtime's three-way comparison against 0.
template <typename OpT>
struct LowerCompare : IdrPattern<OpT> {
  using IdrPattern<OpT>::IdrPattern;
  LogicalResult matchAndRewrite(OpT op, typename OpT::Adaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    Value order = this->runtime.call(rewriter, loc, op.getHelper(), rewriter.getI32Type(),
                                     ValueRange{adaptor.getLhs(), adaptor.getRhs()});
    arith::CmpIPredicate predicate;
    switch (op.getPredicate()) {
    case CmpPredicate::eq:
      predicate = arith::CmpIPredicate::eq;
      break;
    case CmpPredicate::lt:
      predicate = arith::CmpIPredicate::slt;
      break;
    case CmpPredicate::lte:
      predicate = arith::CmpIPredicate::sle;
      break;
    case CmpPredicate::gt:
      predicate = arith::CmpIPredicate::sgt;
      break;
    case CmpPredicate::gte:
      predicate = arith::CmpIPredicate::sge;
      break;
    }
    Value zero = arith::ConstantOp::create(rewriter, loc, rewriter.getI32IntegerAttr(0));
    rewriter.replaceOpWithNewOp<arith::CmpIOp>(op, predicate, order, zero);
    return success();
  }
};

template <typename... Ops>
void addRuntimeCalls(RewritePatternSet &patterns, const TypeConverter &converter,
                     Layouts &layouts, Runtime &runtime) {
  auto add = [&]<typename OpT>() {
    if constexpr (!OpT::template hasTrait<CallsRuntime>() || smallCaseInline<OpT>)
      return;
    else if constexpr (requires(OpT op) { op.getPredicate(); })
      patterns.add<LowerCompare<OpT>>(converter, patterns.getContext(), layouts, runtime);
    else
      patterns.add<LowerRuntimeCall<OpT>>(converter, patterns.getContext(), layouts, runtime);
  };
  (add.template operator()<Ops>(), ...);
}

} // namespace

void populatePatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                      Layouts &layouts, Runtime &runtime) {
  MLIRContext *ctx = patterns.getContext();
  populateCountingPatterns(patterns, converter, layouts, runtime);
  populateBigPatterns(patterns, converter, layouts, runtime);
  patterns.add<LowerCon, LowerTag, LowerField, LowerConstant, LowerCrash, LowerMayLoop,
               LowerPoison, LowerSelect, LowerToChar, LowerDivision<DivOp>, LowerDivision<ModOp>,
               LowerPending, LowerDestOf, LowerDestWrite, LowerAsItself<LinEnterOp>,
               LowerAsItself<LinUseOp>, LowerAsItself<NatToBigOp>>(
      converter, ctx, layouts, runtime);
  // Every op with the trait, which declares the op's runtime call: the op
  // list is the dialect's own.
  addRuntimeCalls<
#define GET_OP_LIST
#include "idr/IdrOps.cc.inc"
      >(patterns, converter, layouts, runtime);
}

} // namespace idr::lower
