// What is known of the integers at one guard, as a system of linear
// constraints over the integers that MLIR's Presburger library decides
// exactly. A column is an SSA integer, as its latest value at the guard, or
// an array's length, or a witness the encoding needs. Every constraint is
// true of the run: a value's range (MLIR's integer range analysis, else its
// type's, within the bounds a loop keeps its carried values in), its
// definition by a linear op or by a guard, which gives its operand (that
// the guard held is a fact of the path to it), the condition each enclosing
// branch took, a Euclidean quotient of a value the system has already
// proved non-negative by a positive constant, and a masked word
// `x & (c - 1)` below `c` when `c` is already a positive power of two,
// doubling included when the double stays below the sign, and the array's
// length is `c`. A constraint left out only makes the system prove less, so
// an op the encoding does not know is a column with its range alone.
//
// Integers are machine words, which wrap: `x + y` is `x + y - 2^w k` for
// some k in [-1, 1] (k = 0 under nsw, whose overflow is no value), and an
// unsigned comparison compares `x + 2^w b`, b in [0, 1], within [0, 2^w).
// Both are exact, so wrapping never makes the system claim a value it
// cannot have.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/Transforms/InBounds.h"

#include "mlir/Analysis/Presburger/IntegerRelation.h"
#include "mlir/Analysis/Presburger/PresburgerSpace.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/IR/Matchers.h"

#include "llvm/ADT/STLExtras.h"

#include <algorithm>
#include <limits>

using namespace mlir;
using llvm::DynamicAPInt;
using mlir::presburger::IntegerPolyhedron;
using mlir::presburger::PresburgerSpace;

namespace idr::inbounds {

namespace {

// Past this many definitions followed, the rest stay columns with ranges.
constexpr unsigned definitionLimit = 96;

template <typename Map>
SmallVector<Value> inColumnOrder(const Map &map) {
  SmallVector<std::pair<unsigned, Value>> sorted;
  for (auto [value, column] : map)
    sorted.push_back({column, value});
  llvm::sort(sorted, [](const auto &a, const auto &b) { return a.first < b.first; });
  SmallVector<Value> out;
  for (auto &entry : sorted)
    out.push_back(entry.second);
  return out;
}

} // namespace

Linear Linear::of(unsigned column) {
  Linear e;
  e.terms.push_back({column, DynamicAPInt(1)});
  return e;
}

Linear Linear::constantOf(const DynamicAPInt &k) {
  Linear e;
  e.constant = k;
  return e;
}

Linear &Linear::plus(const Linear &other, const DynamicAPInt &k) {
  for (const auto &[column, c] : other.terms)
    terms.push_back({column, c * k});
  constant += other.constant * k;
  return *this;
}

Linear &Linear::plus(int64_t k) {
  constant += k;
  return *this;
}

Linear operator-(Linear a, const Linear &b) { return a.plus(b, DynamicAPInt(-1)); }
Linear operator+(Linear a, const Linear &b) { return a.plus(b, DynamicAPInt(1)); }

DynamicAPInt power(unsigned width) {
  DynamicAPInt p(1);
  for (unsigned i = 0; i < width; ++i)
    p *= 2;
  return p;
}

std::optional<unsigned> widthOf(Type type) {
  if (type.isIndex())
    return 0;
  if (auto integer = dyn_cast<IntegerType>(type);
      integer && integer.getWidth() > 1 && integer.getWidth() <= 64)
    return integer.getWidth();
  return std::nullopt;
}

bool isColumn(Value value) { return widthOf(value.getType()).has_value(); }

System::System(const Lengths &lengths, std::function<bool(Value)> admissible,
               CarriedBounds carried, Related related)
    : lengths(lengths), admissible(std::move(admissible)), carried(std::move(carried)),
      related(std::move(related)) {}

Linear System::of(Value value) {
  if (auto it = columns.find(value); it != columns.end())
    return Linear::of(it->second);
  unsigned column = count++;
  columns[value] = column;
  if (std::optional<Bounds> bounds = rangeOf(value))
    within(Linear::of(column), bounds->first, bounds->second);
  if (admissible(value))
    define(value, Linear::of(column));
  return Linear::of(column);
}

// That array's length column, reached without a column or a definition of
// its own, when `length` is the array's dimension, or the clamp at 0 of a
// size the length relation gives the array (what the dimension of an array
// made here folds to); else its own column.
Linear System::sizeOf(Value length, std::optional<Value> array) {
  if (std::optional<Value> measuredArray = measured(length))
    return lengthOf(*measuredArray);
  std::optional<Value> size = clampOf(length);
  if (array && size && related && related(*size, *array)) {
    lengthIs(*size, *array);
    return lengthOf(*array);
  }
  return of(length);
}

Linear System::lengthOf(Value array) {
  Value root = arrayRoot(array);
  if (auto it = lengthColumns.find(root); it != lengthColumns.end())
    return Linear::of(it->second);
  unsigned column = count++;
  lengthColumns[root] = column;
  atLeastZero(Linear::of(column));
  return Linear::of(column);
}

Linear System::fresh(const DynamicAPInt &lo, const DynamicAPInt &hi) {
  Linear e = Linear::of(count++);
  within(e, lo, hi);
  return e;
}

void System::within(const Linear &e, const DynamicAPInt &lo, const DynamicAPInt &hi) {
  atLeastZero(e - Linear::constantOf(lo));
  atLeastZero(Linear::constantOf(hi) - e);
}

std::optional<Bounds> System::rangeOf(Value value) const {
  std::optional<unsigned> width = widthOf(value.getType());
  if (!width || *width == 0)
    return std::nullopt;
  DynamicAPInt half = power(*width - 1);
  Bounds bounds{-half, half - DynamicAPInt(1)};
  // The analysis's range, as idr-narrow reads it. ranges::boundsOf would
  // drop a bound outside the small range, and a word's proof needs the
  // range the analysis gave, signed, at the word's width.
  if (std::optional<ConstantIntRanges> range = lengths.rangeOf(value))
    bounds = {DynamicAPInt(range->smin().getSExtValue()), DynamicAPInt(range->smax().getSExtValue())};
  if (std::optional<Bounds> kept = carried ? carried(value) : std::nullopt)
    bounds = {std::max(bounds.first, kept->first), std::min(bounds.second, kept->second)};
  return bounds;
}

void System::compare(arith::CmpIPredicate predicate, Value x, Value y, bool holds) {
  std::optional<unsigned> width = widthOf(x.getType());
  if (!width)
    return;
  if (!holds)
    predicate = arith::invertPredicate(predicate);
  using P = arith::CmpIPredicate;
  bool isUnsigned = llvm::is_contained({P::ult, P::ule, P::ugt, P::uge}, predicate);
  if (isUnsigned && *width == 0)
    return;
  Linear a = isUnsigned ? unsignedOf(x, *width) : of(x);
  Linear b = isUnsigned ? unsignedOf(y, *width) : of(y);
  switch (predicate) {
  case P::eq: zero(a - b); return;
  case P::ne: return;
  case P::slt: case P::ult: atLeastZero((b - a).plus(-1)); return;
  case P::sle: case P::ule: atLeastZero(b - a); return;
  case P::sgt: case P::ugt: atLeastZero((a - b).plus(-1)); return;
  case P::sge: case P::uge: atLeastZero(a - b); return;
  }
}

void System::assume(Value condition, bool holds) {
  if (!admissible(condition))
    return;
  APInt constant;
  if (matchPattern(condition, m_ConstantInt(&constant))) {
    if (!constant.isZero() != holds)
      impossible();
    return;
  }
  if (auto cmp = condition.getDefiningOp<arith::CmpIOp>())
    return compare(cmp.getPredicate(), cmp.getLhs(), cmp.getRhs(), holds);
  if (auto both = condition.getDefiningOp<arith::AndIOp>(); both && holds) {
    assume(both.getLhs(), true);
    assume(both.getRhs(), true);
  }
  if (auto either = condition.getDefiningOp<arith::OrIOp>(); either && !holds) {
    assume(either.getLhs(), false);
    assume(either.getRhs(), false);
  }
  if (auto flip = condition.getDefiningOp<arith::XOrIOp>()) {
    APInt k;
    if (matchPattern(flip.getRhs(), m_ConstantInt(&k)))
      assume(flip.getLhs(), holds != !k.isZero());
    else if (matchPattern(flip.getLhs(), m_ConstantInt(&k)))
      assume(flip.getRhs(), holds != !k.isZero());
  }
}

SmallVector<Value> System::roots() const { return inColumnOrder(lengthColumns); }

SmallVector<Value> System::values() const { return inColumnOrder(columns); }

// Its length is the larger of the two, and equal to one, which a witness z
// in [0, 1] chooses (no length or size reaches 2^63).
void System::lengthIs(Value size, Value array) {
  if (stated.insert({size, arrayRoot(array)}).second)
    zero(lengthOf(array) - clamped(size));
}

bool System::sameClamp(Value a, Value b) {
  if (!a.getType().isInteger(64) || !b.getType().isInteger(64))
    return false;
  return emptyWith((clamped(a) - clamped(b)).plus(-1)) && emptyWith((clamped(b) - clamped(a)).plus(-1));
}

bool System::emptyWith(const Linear &extra) const {
  IntegerPolyhedron polyhedron(PresburgerSpace::getSetSpace(count));
  auto dense = [&](const Linear &e) {
    SmallVector<DynamicAPInt> row(count + 1, DynamicAPInt(0));
    for (const auto &[column, c] : e.terms)
      row[column] += c;
    row[count] += e.constant;
    return row;
  };
  for (const Row &row : rows) {
    if (row.equality)
      polyhedron.addEquality(dense(row.e));
    else
      polyhedron.addInequality(dense(row.e));
  }
  polyhedron.addInequality(dense(extra));
  return polyhedron.isIntegerEmpty();
}

bool System::nonNegative(Value value) {
  return isColumn(value) && emptyWith(Linear::constantOf(DynamicAPInt(-1)) - of(value));
}

// `max(value, 0)`, below 2^63: a length. A value whose range is already at
// least 0 is its own clamp, and needs no witness.
Linear System::clamped(Value value) {
  if (std::optional<Bounds> range = rangeOf(value); range && range->first >= 0)
    return of(value);
  DynamicAPInt big = power(63);
  Linear n = of(value);
  Linear length = fresh(DynamicAPInt(0), big);
  Linear z = fresh(DynamicAPInt(0), DynamicAPInt(1));
  atLeastZero(length - n);
  atLeastZero(Linear(n).plus(z, big) - length);
  atLeastZero((Linear::constantOf(big) - length).plus(z, -big));
  return length;
}

// `x` as an unsigned word of `width` bits.
Linear System::unsignedOf(Value x, unsigned width) {
  DynamicAPInt wrap = power(width);
  Linear u = fresh(DynamicAPInt(0), wrap - DynamicAPInt(1));
  Linear b = fresh(DynamicAPInt(0), DynamicAPInt(1));
  zero(u - of(x) - Linear().plus(b, wrap));
  return u;
}

// `v` is `e` wrapped to `width` bits: e - 2^width k for k in [-bound, bound].
void System::wrapped(const Linear &v, Linear e, unsigned width, bool noWrap, int64_t bound) {
  if (!noWrap)
    e.plus(fresh(DynamicAPInt(-bound), DynamicAPInt(bound)), -power(width));
  zero(v - e);
}

void System::define(Value value, const Linear &v) {
  Operation *def = value.getDefiningOp();
  if (!def || ++definitions > definitionLimit)
    return;
  unsigned width = *widthOf(value.getType());
  auto noWrap = [](auto op) {
    return arith::bitEnumContainsAny(op.getOverflowFlags(), arith::IntegerOverflowFlags::nsw);
  };
  APInt k;
  if (matchPattern(value, m_ConstantInt(&k)))
    return zero(v - Linear::constantOf(DynamicAPInt(k.getSExtValue())));
  // A guard that returned gave its operand. That its condition held is the
  // path's fact, stated once there; here it is only the value.
  if (auto guard = dyn_cast<GuardOpInterface>(def); guard && isColumn(guard.getGuarded()))
    return zero(v - of(guard.getGuarded()));
  if (auto add = dyn_cast<arith::AddIOp>(def); add && width)
    return wrapped(v, of(add.getLhs()) + of(add.getRhs()), width, noWrap(add), 1);
  if (auto sub = dyn_cast<arith::SubIOp>(def); sub && width)
    return wrapped(v, of(sub.getLhs()) - of(sub.getRhs()), width, noWrap(sub), 1);
  if (auto mul = dyn_cast<arith::MulIOp>(def); mul && width) {
    Value other = mul.getLhs();
    if (!matchPattern(mul.getRhs(), m_ConstantInt(&k))) {
      other = mul.getRhs();
      if (!matchPattern(mul.getLhs(), m_ConstantInt(&k)))
        return;
    }
    int64_t c = k.getSExtValue();
    int64_t bound = c == std::numeric_limits<int64_t>::min() ? std::numeric_limits<int64_t>::max()
                                                              : std::max<int64_t>(c < 0 ? -c : c, 1);
    return wrapped(v, Linear().plus(of(other), DynamicAPInt(c)), width, noWrap(mul), bound);
  }
  if (auto ext = dyn_cast<arith::ExtSIOp>(def); ext && isColumn(ext.getIn()))
    return zero(v - of(ext.getIn()));
  if (auto ext = dyn_cast<arith::ExtUIOp>(def); ext && isColumn(ext.getIn())) {
    unsigned in = *widthOf(ext.getIn().getType());
    return zero(v - unsignedOf(ext.getIn(), in));
  }
  // An index is at most 64 bits, so an index made i64 keeps its value.
  if (auto cast = dyn_cast<arith::IndexCastOp>(def);
      cast && cast.getIn().getType().isIndex() && value.getType().isInteger(64))
    return zero(v - of(cast.getIn()));
  if (auto dim = dyn_cast<memref::DimOp>(def)) {
    if (std::optional<Value> array = dimensionOf(dim))
      zero(v - lengthOf(*array));
    return;
  }
  if (auto max = dyn_cast<arith::MaxSIOp>(def)) {
    atLeastZero(v - of(max.getLhs()));
    atLeastZero(v - of(max.getRhs()));
    return;
  }
  if (auto min = dyn_cast<arith::MinSIOp>(def)) {
    atLeastZero(of(min.getLhs()) - v);
    atLeastZero(of(min.getRhs()) - v);
  }
}

} // namespace idr::inbounds
