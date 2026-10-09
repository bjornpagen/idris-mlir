// The guards: each folds to its operand where the operand shows that its
// condition holds, and narrows the operand's range by the condition. And
// what every folder of a total op and the six pure total ops ask of them:
// whether a condition holds of constants, and when a pure total op may run
// before the guard of its operand.

#include "idr/Idr.h"

#include "mlir/IR/Matchers.h"

#include "idris_rt.h"

#include <algorithm>

import idr.fold;

using namespace mlir;
using namespace idr;

//===----------------------------------------------------------------------===//
// The conditions
//===----------------------------------------------------------------------===//

namespace {

// The number of operands a guard of `kind` checks.
size_t arity(CheckKind kind) {
  switch (kind) {
  case CheckKind::InBounds:
    return 2;
  case CheckKind::Range:
    return 3;
  case CheckKind::Nonzero:
  case CheckKind::Nonempty:
  case CheckKind::Byte:
  case CheckKind::Finite:
    return 1;
  }
  llvm_unreachable("a guard kind");
}

} // namespace

bool idr::checkHolds(CheckKind kind, ArrayRef<Attribute> constants) {
  if (constants.size() != arity(kind) || llvm::is_contained(constants, Attribute()))
    return false;
  auto word = [&](size_t at) { return dyn_cast<IntegerAttr>(constants[at]); };
  switch (kind) {
  case CheckKind::Nonzero:
    if (auto big = dyn_cast<BigAttr>(constants[0]))
      return big.getValue() != "0";
    return word(0) && !word(0).getValue().isZero();
  case CheckKind::InBounds:
    return word(0) && word(1) && !word(0).getValue().isNegative() &&
           word(0).getValue().slt(word(1).getValue());
  case CheckKind::Nonempty: {
    auto str = dyn_cast<StringAttr>(constants[0]);
    return str && !str.getValue().empty();
  }
  case CheckKind::Byte:
    return word(0) && !word(0).getValue().isNegative() && word(0).getValue().isIntN(8);
  case CheckKind::Finite: {
    auto value = dyn_cast<FloatAttr>(constants[0]);
    return value && value.getValue().isFinite();
  }
  case CheckKind::Range: {
    if (!word(0) || !word(1) || !word(2))
      return false;
    APInt offset = word(0).getValue(), count = word(1).getValue();
    bool overflow = false;
    APInt end = offset.sadd_ov(count, overflow);
    return !offset.isNegative() && !count.isNegative() && !overflow &&
           end.sle(word(2).getValue());
  }
  }
  llvm_unreachable("a guard kind");
}

//===----------------------------------------------------------------------===//
// Folding
//===----------------------------------------------------------------------===//

namespace {

// Whether the value `op` checks is the result of a guard identical to it,
// of its kind and with its other operands, which has checked it already.
template <typename Check>
bool checkedBefore(Check op) {
  auto before = op->getOperand(0).template getDefiningOp<Check>();
  return before &&
         llvm::equal(before->getOperands().drop_front(), op->getOperands().drop_front());
}

// The value `op` checks, where its condition holds of the constants that
// folding or constant propagation knows its operands to be, where `known`
// says it holds of the operand, or where an identical guard checked it.
// Nothing otherwise: a guard that would crash keeps its crash, and what
// only an analysis proves is idr-in-bounds's to remove.
template <typename Check>
OpFoldResult foldCheck(Check op, CheckKind kind, ArrayRef<Attribute> constants, bool known) {
  if (known || checkHolds(kind, constants) || checkedBefore(op))
    return op->getOperand(0);
  return {};
}

} // namespace

OpFoldResult CheckNonzeroOp::fold(FoldAdaptor adaptor) {
  return foldCheck(*this, CheckKind::Nonzero, adaptor.getOperands(), knownNonZero(getValue()));
}

OpFoldResult CheckInBoundsOp::fold(FoldAdaptor adaptor) {
  return foldCheck(*this, CheckKind::InBounds, adaptor.getOperands(), false);
}

// A string built with a character or a number in it is not empty, which
// lets a head read the character off the string it was built from.
OpFoldResult CheckNonemptyOp::fold(FoldAdaptor adaptor) {
  return foldCheck(*this, CheckKind::Nonempty, adaptor.getOperands(), knownNonEmpty(getStr()));
}

OpFoldResult CheckByteOp::fold(FoldAdaptor adaptor) {
  return foldCheck(*this, CheckKind::Byte, adaptor.getOperands(), false);
}

OpFoldResult CheckFiniteOp::fold(FoldAdaptor adaptor) {
  return foldCheck(*this, CheckKind::Finite, adaptor.getOperands(), knownFinite(getValue()));
}

OpFoldResult CheckRangeOp::fold(FoldAdaptor adaptor) {
  return foldCheck(*this, CheckKind::Range, adaptor.getOperands(), false);
}

//===----------------------------------------------------------------------===//
// Ranges
//===----------------------------------------------------------------------===//

namespace {

// `range`, an i64's, narrowed to the signed interval [lo, hi] the guard's
// condition leaves. Where it leaves nothing the guard always crashes and
// nothing reads its result, so the range stays as it was.
ConstantIntRanges within(const ConstantIntRanges &range, int64_t lo, int64_t hi) {
  if (range.smin().getBitWidth() != 64 || lo > hi)
    return range;
  ConstantIntRanges narrowed = range.intersection(ConstantIntRanges::fromSigned(
      APInt(64, static_cast<uint64_t>(lo), /*isSigned=*/true),
      APInt(64, static_cast<uint64_t>(hi), /*isSigned=*/true)));
  if (narrowed.smin().sgt(narrowed.smax()) || narrowed.umin().ugt(narrowed.umax()))
    return range;
  return narrowed;
}

} // namespace

// Not zero: an end of the range at zero moves past it. A big's range is
// its value's, as idr.ranges states it, so the same holds of it.
void CheckNonzeroOp::inferResultRanges(ArrayRef<ConstantIntRanges> ranges,
                                       SetIntRangeFn setResultRange) {
  const ConstantIntRanges &range = ranges[0];
  unsigned width = range.umin().getBitWidth();
  // No integer the analysis sees, or zero alone, which always crashes.
  if (width < 2 || range.umax().isZero() || (range.smin().isZero() && range.smax().isZero())) {
    setResultRange(getChecked(), range);
    return;
  }
  APInt one(width, 1);
  setResultRange(getChecked(),
                 ConstantIntRanges(range.umin().isZero() ? one : range.umin(), range.umax(),
                                   range.smin().isZero() ? one : range.smin(),
                                   range.smax().isZero() ? APInt::getAllOnes(width)
                                                         : range.smax()));
}

// At least 0, and below the length, which is at most its range's greatest
// value.
void CheckInBoundsOp::inferResultRanges(ArrayRef<ConstantIntRanges> ranges,
                                        SetIntRangeFn setResultRange) {
  const APInt &longest = ranges[1].smax();
  if (longest.getBitWidth() != 64 || !longest.isStrictlyPositive()) {
    setResultRange(getChecked(), ranges[0]);
    return;
  }
  setResultRange(getChecked(), within(ranges[0], 0, longest.getSExtValue() - 1));
}

void CheckByteOp::inferResultRanges(ArrayRef<ConstantIntRanges> ranges,
                                    SetIntRangeFn setResultRange) {
  setResultRange(getChecked(), within(ranges[0], 0, 255));
}

// At least 0, and at most the size's greatest value less the least count,
// which is not negative either.
void CheckRangeOp::inferResultRanges(ArrayRef<ConstantIntRanges> ranges,
                                     SetIntRangeFn setResultRange) {
  const APInt &count = ranges[1].smin(), &size = ranges[2].smax();
  if (count.getBitWidth() != 64 || size.getBitWidth() != 64 || size.isNegative()) {
    setResultRange(getChecked(), ranges[0]);
    return;
  }
  int64_t least = std::max<int64_t>(count.getSExtValue(), 0);
  setResultRange(getChecked(), within(ranges[0], 0, size.getSExtValue() - least));
}

//===----------------------------------------------------------------------===//
// Speculation
//===----------------------------------------------------------------------===//

namespace {

// The guard each pure total op takes on the operand it guards.
std::optional<CheckKind> guardOf(Operation *op) {
  return TypeSwitch<Operation *, std::optional<CheckKind>>(op)
      .Case<DivOp, ModOp>([](auto) { return CheckKind::Nonzero; })
      .Case([](ToByteOp) { return CheckKind::Byte; })
      .Case([](ToIntOp) { return CheckKind::Finite; })
      .Case([](StrIndexOp) { return CheckKind::InBounds; })
      .Case([](StrHeadOp) { return CheckKind::Nonempty; })
      .Default(std::nullopt);
}

// The kind of the guard `op`, or nothing when it is no guard.
std::optional<CheckKind> kindOf(Operation *op) {
  if (!op)
    return std::nullopt;
  return TypeSwitch<Operation *, std::optional<CheckKind>>(op)
      .Case([](CheckNonzeroOp) { return CheckKind::Nonzero; })
      .Case([](CheckInBoundsOp) { return CheckKind::InBounds; })
      .Case([](CheckNonemptyOp) { return CheckKind::Nonempty; })
      .Case([](CheckByteOp) { return CheckKind::Byte; })
      .Case([](CheckFiniteOp) { return CheckKind::Finite; })
      .Case([](CheckRangeOp) { return CheckKind::Range; })
      .Default(std::nullopt);
}

// Whether `value`, the operand of `op` that its guard of `kind` checks, is
// that guard's result. An index counts only past the guard against the
// length of the op's own string: one against another string's length
// proves nothing of this one.
bool passedGuard(Operation *op, CheckKind kind, Value value) {
  Operation *guard = value.getDefiningOp();
  if (kindOf(guard) != kind)
    return false;
  if (kind != CheckKind::InBounds)
    return true;
  auto index = dyn_cast<StrIndexOp>(op);
  auto length = cast<CheckInBoundsOp>(guard).getLength().getDefiningOp<StrLengthOp>();
  return index && length && length.getStr() == index.getStr();
}

// The length of a constant string as the runtime counts it, which is what
// idr.str.length folds to; null for any other string.
Attribute constantLength(Value str) {
  StringAttr text;
  if (!matchPattern(str, m_Constant(&text)))
    return {};
  fold::Scope scope(str.getContext());
  return fold::wrapped(IntegerType::get(str.getContext(), 64),
                       idris_rt_str_length(scope.str(text)));
}

// The constants the guard of `kind` would check where `value` is the
// operand of `op` it guards: the value, and for an index the length of the
// op's string. A null one is not a constant.
SmallVector<Attribute, 2> checkedConstants(Operation *op, CheckKind kind, Value value) {
  Attribute constant;
  matchPattern(value, m_Constant(&constant));
  if (kind != CheckKind::InBounds)
    return {constant};
  auto index = dyn_cast<StrIndexOp>(op);
  return {constant, index ? constantLength(index.getStr()) : Attribute()};
}

} // namespace

Speculation::Speculatability idr::checkSpeculatability(Operation *op,
                                                       ArrayRef<unsigned> guarded) {
  std::optional<CheckKind> kind = guardOf(op);
  if (!kind)
    return Speculation::NotSpeculatable;
  for (unsigned number : guarded) {
    Value value = op->getOperand(number);
    if (!passedGuard(op, *kind, value) && !checkHolds(*kind, checkedConstants(op, *kind, value)))
      return Speculation::NotSpeculatable;
  }
  return Speculation::Speculatable;
}
