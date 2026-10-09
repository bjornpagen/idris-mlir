// idr.lower:checks: the patterns of the guards. A guard is the test of its
// condition, the crash with its cause where the test fails, and then its
// operand, which the op it guards takes. That op's own lowering tests
// nothing, so a guard a proof removed leaves no test behind.

export module idr.lower:checks;

import idr.mlir;
import idr.dialect;
import idr.layout;

import :idrPattern;
import :runtime;
import :words;

using namespace mlir;

namespace idr::lower {

namespace {

// A guard's operands as the conversion gives them. Each is one value: an
// integer, a double, a string's pointer or a big's word.
template <typename OpT>
using Converted = typename OpT::template GenericAdaptor<ArrayRef<ValueRange>>;

Value compare(OpBuilder &b, Location loc, arith::CmpIPredicate predicate, Value x, Value y) {
  return arith::CmpIOp::create(b, loc, predicate, x, y);
}

// Where each guard fails.

// The integer 0, or the big 0, which is the small word 1.
Value fails(CheckNonzeroOp op, Converted<CheckNonzeroOp> in, OpBuilder &b, Location loc,
            Runtime &) {
  Value value = in.getValue().front();
  Type type = op.getValue().getType();
  Value zero = isa<IntegerType>(type)
                   ? Value(arith::ConstantOp::create(b, loc, b.getIntegerAttr(type, 0)))
                   : constantI64(b, loc, 1);
  return compare(b, loc, arith::CmpIPredicate::eq, value, zero);
}

// An index from the length on; a negative index is a large unsigned one.
Value fails(CheckInBoundsOp, Converted<CheckInBoundsOp> in, OpBuilder &b, Location loc, Runtime &) {
  return compare(b, loc, arith::CmpIPredicate::uge, in.getIndex().front(),
                 in.getLength().front());
}

// A string of no characters.
Value fails(CheckNonemptyOp, Converted<CheckNonemptyOp> in, OpBuilder &b, Location loc,
            Runtime &runtime) {
  Value length = runtime.call(b, loc, "idris_rt_str_length", b.getI64Type(), in.getStr().front());
  return compare(b, loc, arith::CmpIPredicate::eq, length, constantI64(b, loc, 0));
}

// A value above 255; a negative one is a large unsigned one.
Value fails(CheckByteOp, Converted<CheckByteOp> in, OpBuilder &b, Location loc, Runtime &) {
  return compare(b, loc, arith::CmpIPredicate::ugt, in.getValue().front(),
                 constantI64(b, loc, 255));
}

// NaN or an infinity.
Value fails(CheckFiniteOp, Converted<CheckFiniteOp> in, OpBuilder &b, Location loc, Runtime &) {
  Value finite = math::IsFiniteOp::create(b, loc, in.getValue().front());
  Value yes = arith::ConstantOp::create(b, loc, b.getBoolAttr(true));
  return arith::XOrIOp::create(b, loc, finite, yes);
}

// A negative offset or count, an offset past the size, or more bytes than
// the size has after the offset. That room cannot overflow once the offset
// is within the size; where it is not, the room wraps, and a test before
// it has already failed.
Value fails(CheckRangeOp, Converted<CheckRangeOp> in, OpBuilder &b, Location loc, Runtime &) {
  Value offset = in.getOffset().front(), count = in.getCount().front(),
        size = in.getSize().front();
  Value zero = constantI64(b, loc, 0);
  Value room = arith::SubIOp::create(b, loc, size, offset);
  Value outside = compare(b, loc, arith::CmpIPredicate::slt, offset, zero);
  for (Value test : {compare(b, loc, arith::CmpIPredicate::slt, count, zero),
                     compare(b, loc, arith::CmpIPredicate::sgt, offset, size),
                     compare(b, loc, arith::CmpIPredicate::sgt, count, room)})
    outside = arith::OrIOp::create(b, loc, outside, test);
  return outside;
}

// The crash is at the guard's location, which is the partial op's, so its
// message is the one that op's crash has.
template <typename OpT>
struct LowerCheck : IdrPattern<OpT> {
  using IdrPattern<OpT>::IdrPattern;
  LogicalResult matchAndRewrite(OpT op, typename IdrPattern<OpT>::OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    this->runtime.crashIf(rewriter, loc, fails(op, adaptor, rewriter, loc, this->runtime),
                          op.getCause());
    // The checked operand is the first.
    rewriter.replaceOpWithMultiple(op, {SmallVector<Value>(adaptor.getOperands().front())});
    return success();
  }
};

} // namespace

// The patterns of the guards.
export void populateCheckPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                                  layout::Layouts &layouts, Runtime &runtime) {
  patterns.add<LowerCheck<CheckNonzeroOp>, LowerCheck<CheckInBoundsOp>,
               LowerCheck<CheckNonemptyOp>, LowerCheck<CheckByteOp>, LowerCheck<CheckFiniteOp>,
               LowerCheck<CheckRangeOp>>(converter, patterns.getContext(), layouts, runtime);
}

} // namespace idr::lower
