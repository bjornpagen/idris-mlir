// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The patterns of the guards. A guard is the test of its condition, the crash
// with its cause where the test fails, and then its operand, which the op it
// guards takes. That op's own lowering tests nothing, so a guard a proof
// removed leaves no test behind.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Layout.h"
#include "idr/Conversion/Arrays.h"
#include "idr/Conversion/IdrPattern.h"
#include "idr/Conversion/Patterns.h"
#include "idr/Conversion/Runtime.h"
#include "idr/Conversion/Words.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Math/IR/Math.h"
#include "mlir/Transforms/DialectConversion.h"

using namespace mlir;

namespace idr::conversion {

namespace {

// A guard's operands as the conversion gives them: an integer, a double, a
// string's pointer or a big's word, or an array's components.
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
                   : Value(arith::ConstantIntOp::create(b, loc, 1, 64));
  return compare(b, loc, arith::CmpIPredicate::eq, value, zero);
}

// An index from the length of what it indexes on: a string's characters,
// which the runtime counts, or an array's size, which its value holds; a
// negative index is a large unsigned one.
Value fails(CheckInBoundsOp op, Converted<CheckInBoundsOp> in, OpBuilder &b, Location loc,
            Runtime &runtime) {
  Type indexed = unrestricted(op.getIndexed().getType());
  ValueRange what = in.getIndexed();
  auto array = dyn_cast<MemRefType>(indexed);
  Value length = array ? asWord(b, loc, unpack(b, loc, array, what).sizes.front())
                       : runtime.call(b, loc, "idris_rt_str_length", b.getI64Type(), what.front());
  return compare(b, loc, arith::CmpIPredicate::uge, in.getIndex().front(), length);
}

// A string of no characters.
Value fails(CheckNonemptyOp, Converted<CheckNonemptyOp> in, OpBuilder &b, Location loc,
            Runtime &runtime) {
  Value length = runtime.call(b, loc, "idris_rt_str_length", b.getI64Type(), in.getStr().front());
  return compare(b, loc, arith::CmpIPredicate::eq, length,
                 arith::ConstantIntOp::create(b, loc, 0, 64));
}

// A value above 255; a negative one is a large unsigned one.
Value fails(CheckByteOp, Converted<CheckByteOp> in, OpBuilder &b, Location loc, Runtime &) {
  return compare(b, loc, arith::CmpIPredicate::ugt, in.getValue().front(),
                 arith::ConstantIntOp::create(b, loc, 255, 64));
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
  Value zero = arith::ConstantIntOp::create(b, loc, 0, 64);
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
    // The operand the guard guards, its first, is its result.
    rewriter.replaceOpWithMultiple(op, {SmallVector<Value>(adaptor.getOperands().front())});
    return success();
  }
};

} // namespace

// The patterns of the guards.
void populateCheckPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                           const Layouts &layouts, Runtime &runtime) {
  patterns.add<LowerCheck<CheckNonzeroOp>, LowerCheck<CheckInBoundsOp>,
               LowerCheck<CheckNonemptyOp>, LowerCheck<CheckByteOp>, LowerCheck<CheckFiniteOp>,
               LowerCheck<CheckRangeOp>>(converter, patterns.getContext(), layouts, runtime);
}

} // namespace idr::conversion
