// idr.inbounds:masks: `x & (c - 1)` is below `c` when `c` is a positive power
// of two. The mask is then the low bits, and those bits of any word are a
// remainder in `[0, c)`. The same shape with a capacity the facts do not
// pin to one power of two stays unrelated: nothing here proves the power.
//
// A power of two is a fact already in hand. The value's range is that one
// value, or the value is a shift of 1 by an amount the path keeps in
// `0 .. width-2`, so the bit lands below the sign. A shift by the sign's
// place is the smallest word, whose array is empty, and an amount the path
// does not bound may be that place or past the width, where an Idris shift
// fills with zero.
export module idr.inbounds:masks;

import idr.mlir;
import idr.dialect;

import :joins;
import :lengths;
import :linear;
import :system;

using namespace mlir;
using llvm::DynamicAPInt;

namespace idr::inbounds {

namespace {

// Whether `v` is `2^k` for some `k` in `0 .. width-2`: positive, and below
// the sign.
bool positivePowerOfTwo(const DynamicAPInt &v, unsigned width) {
  if (width < 2 || v < 1 || v > power(width - 2))
    return false;
  DynamicAPInt x = v;
  while (x > 1) {
    if (x % 2 != 0)
      return false;
    x /= 2;
  }
  return true;
}

// Whether every integer the system allows for `value` is at least 0.
bool nonNegative(System &system, Value value) {
  if (!isColumn(value))
    return false;
  return system.emptyWith(Linear::constantOf(DynamicAPInt(-1)) - system.of(value));
}

// Whether every integer the system allows for `value` is at most `hi`.
bool atMost(System &system, Value value, int64_t hi) {
  if (!isColumn(value))
    return false;
  return system.emptyWith(system.of(value) - Linear::constantOf(DynamicAPInt(hi + 1)));
}

// `1` shifted by an amount the system keeps in `0 .. width-2`.
bool shiftedOne(System &system, Value value, unsigned width) {
  Value amount;
  APInt one;
  if (auto arithShift = value.getDefiningOp<arith::ShLIOp>()) {
    if (!matchPattern(arithShift.getLhs(), m_ConstantInt(&one)) || !one.isOne())
      return false;
    amount = arithShift.getRhs();
  } else if (auto idrisShift = value.getDefiningOp<ShlOp>()) {
    if (!matchPattern(idrisShift.getLhs(), m_ConstantInt(&one)) || !one.isOne())
      return false;
    amount = idrisShift.getRhs();
  } else {
    return false;
  }
  // `width - 2` fits a signed word: a column is at most 64 bits.
  return nonNegative(system, amount) && atMost(system, amount, static_cast<int64_t>(width - 2));
}

// Whether `value` is a positive power of two from a fact the system already
// has: a constant, a shift of one, or a range of that one value.
bool provedPowerOfTwo(System &system, Value value, unsigned width) {
  if (width < 2)
    return false;
  APInt constant;
  if (matchPattern(value, m_ConstantInt(&constant)))
    return positivePowerOfTwo(DynamicAPInt(constant.getSExtValue()), width);
  if (shiftedOne(system, value, width))
    return true;
  std::optional<Bounds> bounds = system.rangeOf(value);
  return bounds && bounds->first == bounds->second && positivePowerOfTwo(bounds->first, width);
}

// `mask`, when it is some capacity minus one. The subtraction of one from
// a positive power of two does not wrap, so the bits are exactly that mask.
std::optional<Value> capacityMinusOne(Value mask) {
  APInt k;
  if (auto sub = mask.getDefiningOp<arith::SubIOp>()) {
    if (matchPattern(sub.getRhs(), m_ConstantInt(&k)) && k.isOne())
      return sub.getLhs();
    return std::nullopt;
  }
  if (auto add = mask.getDefiningOp<arith::AddIOp>()) {
    if (matchPattern(add.getRhs(), m_ConstantInt(&k)) && k.isAllOnes())
      return add.getLhs();
    if (matchPattern(add.getLhs(), m_ConstantInt(&k)) && k.isAllOnes())
      return add.getRhs();
  }
  return std::nullopt;
}

} // namespace

// When `index` is `x & (c - 1)`, `c` is a positive power of two the system
// already knows, and `array`'s length is `c`: `0 <= index < c`.
export void relateMask(System &system, Lengths &lengths, DominanceInfo &dominance, Operation *access,
                       Value array, Value index) {
  auto masked = index.getDefiningOp<arith::AndIOp>();
  if (!masked)
    return;
  Value root = arrayRoot(array);
  if (!dominance.properlyDominates(root, access))
    return;
  auto consider = [&](Value operand) {
    std::optional<Value> cap = capacityMinusOne(operand);
    if (!cap || !dominance.properlyDominates(*cap, access))
      return;
    std::optional<unsigned> width = widthOf(cap->getType());
    if (!width || *width < 2 || !provedPowerOfTwo(system, *cap, *width))
      return;
    if (!lengths.related(*cap, array))
      return;
    Linear c = system.of(*cap);
    system.within(c, DynamicAPInt(1), power(*width - 2));
    system.lengthIs(*cap, array);
    Linear i = system.of(index);
    system.atLeastZero(i);
    system.atLeastZero((c - i).plus(-1));
  };
  consider(masked.getLhs());
  consider(masked.getRhs());
}

} // namespace idr::inbounds
