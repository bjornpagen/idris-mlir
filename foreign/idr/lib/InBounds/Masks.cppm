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
//
// Doubling keeps the fact. The value doubled is a positive power of two
// already in hand, and each step is a multiply by 2 or a shift left by 1,
// so a `2^k` becomes `2^(k+1)`. The result stays at most `2^(width-2)`,
// below the sign, when `k` is at most `width-3`: the value before the step
// is then below `2^(width-2)`, and so below `2^(width-1)`. A shift of 1
// whose amount the path keeps that small is the same bound one place
// further, still in `0 .. width-2`. A double that may be of `2^(width-2)`
// reaches the sign bit — the smallest word, whose array is empty — and is
// not given the fact. A value only known to be positive is not a power of
// two, and neither is its double.
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

// Past this many doublings followed, the rest stay unrelated: an answer is
// then only weaker.
constexpr unsigned powerLimit = 96;

// `2^exp` as a signed word. `exp` is at most 62, so the bit sits below the sign.
int64_t place(unsigned exp) { return int64_t(1) << exp; }

// The exponent of `v` when it is `2^k` for a `k` in `0 .. width-2`.
std::optional<unsigned> exponentOf(const DynamicAPInt &v, unsigned width) {
  if (!positivePowerOfTwo(v, width))
    return std::nullopt;
  unsigned exp = 0;
  for (DynamicAPInt x = v; x > 1; x /= 2)
    ++exp;
  return exp;
}

// Whether `value` is the constant `k`.
bool isConstant(Value value, int64_t k) {
  APInt constant;
  return matchPattern(value, m_ConstantInt(&constant)) && constant.getBitWidth() <= 64 &&
         constant.getSExtValue() == k;
}

// The amount, when `value` is `1` shifted by it.
std::optional<Value> shiftOfOne(Value value) {
  APInt one;
  if (auto arithShift = value.getDefiningOp<arith::ShLIOp>()) {
    if (matchPattern(arithShift.getLhs(), m_ConstantInt(&one)) && one.isOne())
      return arithShift.getRhs();
    return std::nullopt;
  }
  if (auto idrisShift = value.getDefiningOp<ShlOp>()) {
    if (matchPattern(idrisShift.getLhs(), m_ConstantInt(&one)) && one.isOne())
      return idrisShift.getRhs();
  }
  return std::nullopt;
}

// The value doubled, when `value` is that value multiplied by 2 or shifted
// left by 1. A shift of the constant 1 is the amount's power, not a double.
std::optional<Value> doubledBase(Value value) {
  if (auto mul = value.getDefiningOp<arith::MulIOp>()) {
    if (isConstant(mul.getRhs(), 2))
      return mul.getLhs();
    if (isConstant(mul.getLhs(), 2))
      return mul.getRhs();
    return std::nullopt;
  }
  if (auto arithShift = value.getDefiningOp<arith::ShLIOp>()) {
    if (isConstant(arithShift.getRhs(), 1))
      return arithShift.getLhs();
    return std::nullopt;
  }
  if (auto idrisShift = value.getDefiningOp<ShlOp>()) {
    if (isConstant(idrisShift.getRhs(), 1))
      return idrisShift.getLhs();
  }
  return std::nullopt;
}

// The greatest amount in `0 .. width-2` the system allows, when every
// amount it allows is in that range.
std::optional<unsigned> shiftExponent(System &system, Value amount, unsigned width) {
  int64_t hi = static_cast<int64_t>(width - 2);
  if (!nonNegative(system, amount) || !atMost(system, amount, hi))
    return std::nullopt;
  unsigned lo = 0;
  unsigned top = width - 2;
  while (lo < top) {
    unsigned mid = lo + (top - lo) / 2;
    if (atMost(system, amount, static_cast<int64_t>(mid)))
      top = mid;
    else
      lo = mid + 1;
  }
  return lo;
}

// A positive power of two known to be at most `2^exp` is at most
// `2^(exp-1)` when the system proves it is below `2^exp`. A bound the
// system does not have leaves `exp`: the range of a shift is often the
// whole word, and that is not a proof that the top power is absent.
unsigned tighten(System &system, Value value, unsigned exp) {
  while (exp > 0 && atMost(system, value, place(exp) - 1))
    --exp;
  return exp;
}

// The greatest `k` in `0 .. width-2` such that every integer `value` may be
// is `2^k'` for some `k' <= k`. None when the facts do not pin it to those
// powers.
std::optional<unsigned> exponent(System &system, Value value, unsigned width, unsigned depth) {
  if (depth > powerLimit || width < 2)
    return std::nullopt;
  std::optional<unsigned> raw;
  APInt constant;
  if (matchPattern(value, m_ConstantInt(&constant)) && constant.getBitWidth() <= 64) {
    raw = exponentOf(DynamicAPInt(constant.getSExtValue()), width);
  } else if (std::optional<Value> amount = shiftOfOne(value)) {
    raw = shiftExponent(system, *amount, width);
  } else if (std::optional<Value> base = doubledBase(value)) {
    // One more place still below the sign: the base is at most
    // `2^(width-3)`, so the double is at most `2^(width-2)`.
    if (std::optional<unsigned> below = exponent(system, *base, width, depth + 1))
      if (*below + 1 <= width - 2)
        raw = *below + 1;
  }
  if (!raw) {
    if (std::optional<Bounds> bounds = system.rangeOf(value);
        bounds && bounds->first == bounds->second)
      raw = exponentOf(bounds->first, width);
  }
  if (!raw)
    return std::nullopt;
  return tighten(system, value, *raw);
}

// Whether `value` is a positive power of two from a fact the system already
// has: a constant, a shift of one, a double of one that stays below the
// sign, or a range of that one value.
bool provedPowerOfTwo(System &system, Value value, unsigned width) {
  return exponent(system, value, width, 0).has_value();
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
