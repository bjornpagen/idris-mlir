// idr.lower:runtimeCalls: the patterns of the ops that call the runtime
// (Idr_CallsRuntime), and of the comparisons whose runtime function orders
// its operands.

export module idr.lower:runtimeCalls;

import idr.mlir;
import idr.dialect;
import idr.layout;

import :idrPattern;
import :runtime;
import :words;

using namespace mlir;

namespace idr::lower {

namespace {

SmallVector<Value> flatten(ArrayRef<ValueRange> operands) {
  SmallVector<Value> values;
  for (ValueRange operand : operands)
    llvm::append_range(values, operand);
  return values;
}

// The runtime function of an op is named after it (Idr_CallsRuntime). Where
// the op's signedness or operand type picks the function, the name ends in
// _s, _u or _f64 and an integer is extended to 64 bits as the signedness
// says. Ops whose result width varies get the result modulo 2^64 and
// truncate it.
template <typename OpT>
constexpr bool returnsWord = llvm::is_one_of<OpT, ToIntOp, StrToIntOp>::value;

// The ops with a lowering of their own: the bigs whose small case is inline
// (:bigs), which call the runtime only on their cold path, and the string
// builders over lists (:strings), which walk the list here.
template <typename OpT>
constexpr bool ownLowering = llvm::is_one_of<OpT, BigAddOp, BigSubOp, BigMulOp, BigPredOp,
                                             BigCmpOp, NatFromBigOp, BigFromIntOp, BigToIntOp,
                                             StrPackOp, StrConcatOp>::value;

template <typename OpT>
std::optional<bool> signedness(OpT op) {
  if constexpr (requires { op.getIsSigned(); })
    return op.getIsSigned();
  return std::nullopt;
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

// An op's precondition (a divisor that is not zero, an index within the
// string) is its guard's, tested before the op (:checks): the call is all
// the op lowers to.
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
    arith::CmpIPredicate predicate = signedPredicate(op.getPredicate());
    Value zero = arith::ConstantOp::create(rewriter, loc, rewriter.getI32IntegerAttr(0));
    rewriter.replaceOpWithNewOp<arith::CmpIOp>(op, predicate, order, zero);
    return success();
  }
};

template <typename... Ops>
void addRuntimeCalls(RewritePatternSet &patterns, const TypeConverter &converter,
                     layout::Layouts &layouts, Runtime &runtime) {
  auto add = [&]<typename OpT>() {
    if constexpr (!OpT::template hasTrait<CallsRuntime>() || ownLowering<OpT>)
      return;
    else if constexpr (requires(OpT op) { op.getPredicate(); })
      patterns.add<LowerCompare<OpT>>(converter, patterns.getContext(), layouts, runtime);
    else
      patterns.add<LowerRuntimeCall<OpT>>(converter, patterns.getContext(), layouts, runtime);
  };
  (add.template operator()<Ops>(), ...);
}

} // namespace

// The patterns of the ops that call the runtime: every op with the trait,
// which declares the op's runtime call; the op list is the dialect's own.
export void populateRuntimeCallPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                                        layout::Layouts &layouts, Runtime &runtime) {
  addRuntimeCalls<
#define GET_OP_LIST
#include "idr/IdrOps.cc.inc"
      >(patterns, converter, layouts, runtime);
}

} // namespace idr::lower
