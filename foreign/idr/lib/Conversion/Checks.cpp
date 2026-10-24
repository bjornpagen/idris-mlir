// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The patterns of the guards. A guard is the test of its condition, the
// crash of its cause at its site where the test fails, and then its
// operand, which the op it guards takes. That op's own lowering tests
// nothing, so a guard a proof removed leaves no test behind. Every
// condition but one is inline arithmetic, the meaning its fold and its
// interval decision instantiate too (Numeric/Inline.h), here over arith,
// on what the guard tests (a string's length, a Double's bits); what a
// handle holds is the runtime's handle table's.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Numeric/Arith.h"
#include "idr/IR/Numeric/Inline.h"
#include "idr/Conversion/Arrays.h"
#include "idr/Conversion/IdrPattern.h"
#include "idr/Conversion/Patterns.h"
#include "idr/Conversion/Runtime.h"
#include "idr/Conversion/Words.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Transforms/DialectConversion.h"

// The runtime's C ABI: the small Integer word's encoding.
#include "idris_rt.h"

using namespace mlir;

namespace idr::conversion {

namespace {

// A guard's operands as the conversion gives them: an integer, a double, a
// string's pointer or a big's word, or an array's components.
template <typename OpT>
using Converted = typename OpT::template GenericAdaptor<ArrayRef<ValueRange>>;

// Where each guard fails, an i1.

// An integer divisor fails where its condition does. An Integer's zero is
// the runtime's small word of 0, an encoding, no integer of the op's:
// essential, the two types a divisor has.
Value fails(CheckNonzeroOp op, Converted<CheckNonzeroOp> in, OpBuilder &b, Location loc,
            Runtime &) {
  Value value = in.getValue().front();
  numeric::Arith d(b, loc);
  if (isa<IntegerType>(op.getValue().getType()))
    return d.negation(numeric::nonzero(d, value)).bit;
  Value zero =
      arith::ConstantIntOp::create(b, loc, static_cast<int64_t>(idris_rt_small_word(0)), 64);
  return d.equal(value, zero).bit;
}

// An index against the length of what it indexes: a string's characters,
// which the runtime counts, or an array's size, which its value holds. The
// length, a word, is compared at the index's own type, a word or an index.
Value fails(CheckInBoundsOp op, Converted<CheckInBoundsOp> in, OpBuilder &b, Location loc,
            Runtime &runtime) {
  Type indexed = unrestricted(op.getIndexed().getType());
  ValueRange what = in.getIndexed();
  auto array = dyn_cast<MemRefType>(indexed);
  Value length = array ? asWord(b, loc, unpack(b, loc, array, what).sizes.front())
                       : runtime.call(b, loc, idr::runtime::Abi<StrLengthOp>::entry, what.front())
                             .getResult();
  Value index = in.getIndex().front();
  if (index.getType() != length.getType())
    length = arith::IndexCastOp::create(b, loc, index.getType(), length);
  numeric::Arith d(b, loc);
  return d.negation(numeric::inBounds(d, index, length)).bit;
}

// A string of no characters, by the runtime's count of them.
Value fails(CheckNonemptyOp, Converted<CheckNonemptyOp> in, OpBuilder &b, Location loc,
            Runtime &runtime) {
  Value length =
      runtime.call(b, loc, idr::runtime::Abi<StrLengthOp>::entry, in.getStr().front()).getResult();
  numeric::Arith d(b, loc);
  return d.negation(numeric::nonempty(d, length)).bit;
}

// NaN or an infinity, by the Double's bits.
Value fails(CheckFiniteOp, Converted<CheckFiniteOp> in, OpBuilder &b, Location loc, Runtime &) {
  Value bits = arith::BitcastOp::create(b, loc, b.getI64Type(), in.getValue().front());
  numeric::Arith d(b, loc);
  return d.negation(numeric::finite(d, bits)).bit;
}

// A handle whose slot holds no string, as the runtime's table says: the
// one test of it, made where the run reaches the guard.
Value fails(CheckHoldsStringOp, Converted<CheckHoldsStringOp> in, OpBuilder &b, Location loc,
            Runtime &runtime) {
  Value holds =
      runtime.call(b, loc, idr::runtime::helper::handleHoldsString, in.getHandle().front())
          .getResult();
  Value yes = arith::ConstantOp::create(b, loc, b.getBoolAttr(true));
  return arith::XOrIOp::create(b, loc, holds, yes);
}

Value fails(CheckRangeOp, Converted<CheckRangeOp> in, OpBuilder &b, Location loc, Runtime &) {
  numeric::Arith d(b, loc);
  return d
      .negation(numeric::inRange(d, in.getOffset().front(), in.getCount().front(),
                                 in.getSize().front()))
      .bit;
}

// A status no byte holds, which no parent could read.
Value fails(CheckByteOp, Converted<CheckByteOp> in, OpBuilder &b, Location loc, Runtime &) {
  numeric::Arith d(b, loc);
  return d.negation(numeric::fitsByte(d, in.getValue().front())).bit;
}

// The crash is the guard's cause at the guard's site, both its own
// properties, never read from its location, given the operand the guard
// guards where the cause's line reads it, as a refuted guard's crash is
// (an exit's status no parent could read).
template <typename OpT>
struct LowerCheck : IdrPattern<OpT> {
  using IdrPattern<OpT>::IdrPattern;
  LogicalResult matchAndRewrite(OpT op, typename IdrPattern<OpT>::OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    // The operand the guard guards, its first, is its result.
    ValueRange guarded = adaptor.getOperands().front();
    this->runtime.crashIf(rewriter, loc, fails(op, adaptor, rewriter, loc, this->runtime),
                          op.getCause(), guarded.take_front(operandsRead(op.getCause())),
                          op.getSite());
    rewriter.replaceOpWithMultiple(op, {SmallVector<Value>(guarded)});
    return success();
  }
};

template <typename... Ops>
void addChecks(RewritePatternSet &patterns, const TypeConverter &converter,
               const Layouts &layouts, Runtime &runtime) {
  auto add = [&]<typename OpT>() {
    if constexpr (OpT::template hasTrait<GuardOpInterface::Trait>())
      patterns.add<LowerCheck<OpT>>(converter, patterns.getContext(), layouts, runtime);
  };
  (add.template operator()<Ops>(), ...);
}

} // namespace

// The patterns of the guards: every op that is one, so that a guard without
// a `fails` above does not compile.
void populateCheckPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                           const Layouts &layouts, Runtime &runtime) {
  addChecks<
#define GET_OP_LIST
#include "idr/IR/IdrOps.cpp.inc"
      >(patterns, converter, layouts, runtime);
}

} // namespace idr::conversion
