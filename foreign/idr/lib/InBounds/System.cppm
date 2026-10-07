// idr.inbounds:system: what is known of the integers at one access, as a
// system of linear constraints over the integers that MLIR's Presburger
// library decides exactly. A column is an SSA integer, as its latest value
// at the access, or an array's length, or a witness the encoding needs.
// Every constraint is true of the run: a value's range (MLIR's integer
// range analysis, else its type's, within the bounds a loop keeps its
// carried values in, induction), its definition by a linear op, the
// condition each enclosing branch took, and a Euclidean quotient of a
// value the system has already proved non-negative by a positive constant.
// A constraint left out only makes the system prove less, so an op the
// encoding does not know is a column with its range alone.
//
// Integers are machine words, which wrap: `x + y` is `x + y - 2^w k` for
// some k in [-1, 1] (k = 0 under nsw, whose overflow is no value), and an
// unsigned comparison compares `x + 2^w b`, b in [0, 1], within [0, 2^w).
// Both are exact, so wrapping never makes the system claim a value it
// cannot have.
export module idr.inbounds:system;

import idr.mlir;
import idr.dialect;
import idr.narrow;

import :joins;
import :linear;

using namespace mlir;
using llvm::DynamicAPInt;
using mlir::presburger::IntegerPolyhedron;
using mlir::presburger::PresburgerSpace;
using namespace mlir::dataflow;

namespace idr::inbounds {

namespace {

// Past this many definitions followed, the rest stay columns with ranges.
constexpr unsigned definitionLimit = 96;

} // namespace

// The least and the greatest value of an integer.
export using Bounds = std::pair<DynamicAPInt, DynamicAPInt>;

// The bounds a loop-carried integer is proven to keep at every iteration;
// none for any other value, or when none is known.
export using CarriedBounds = std::function<std::optional<Bounds>(Value)>;

export class System {
public:
  System(DataFlowSolver &solver, std::function<bool(Value)> admissible,
         CarriedBounds carried = nullptr)
      : solver(solver), admissible(std::move(admissible)), carried(std::move(carried)) {}

  // The column of the integer `value`, with its range, and its definition
  // when it is known at the access (`admissible`).
  Linear of(Value value) {
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

  // Whether `value`'s definition is known at the access this system is for.
  bool known(Value value) const { return admissible(value); }

  // The length of the array `array` (its root's, which views share).
  Linear lengthOf(Value array) {
    Value root = arrayRoot(array);
    if (auto it = lengths.find(root); it != lengths.end())
      return Linear::of(it->second);
    unsigned column = count++;
    lengths[root] = column;
    atLeastZero(Linear::of(column));
    return Linear::of(column);
  }

  // A witness in [lo, hi].
  Linear fresh(const DynamicAPInt &lo, const DynamicAPInt &hi) {
    Linear e = Linear::of(count++);
    within(e, lo, hi);
    return e;
  }

  void atLeastZero(Linear e) { rows.push_back({std::move(e), false}); }
  void zero(Linear e) { rows.push_back({std::move(e), true}); }
  void impossible() { atLeastZero(Linear().plus(-1)); }

  void within(const Linear &e, const DynamicAPInt &lo, const DynamicAPInt &hi) {
    atLeastZero(e - Linear::constantOf(lo));
    atLeastZero(Linear::constantOf(hi) - e);
  }

  // The range of `value`: the analysis's, else its type's, within the
  // bounds its loop keeps it in; none for an index, whose width is the
  // target's.
  std::optional<Bounds> rangeOf(Value value) const {
    std::optional<unsigned> width = widthOf(value.getType());
    if (!width || *width == 0)
      return std::nullopt;
    DynamicAPInt half = power(*width - 1);
    Bounds bounds{-half, half - DynamicAPInt(1)};
    // The analysis's range, as idr-narrow reads it. ranges::boundsOf would
    // drop a bound outside the small range, and a word's proof needs the
    // range the analysis gave, signed, at the word's width.
    if (std::optional<ConstantIntRanges> range = narrow::rangeOf(solver, value))
      bounds = {DynamicAPInt(range->smin().getSExtValue()), DynamicAPInt(range->smax().getSExtValue())};
    if (std::optional<Bounds> kept = carried ? carried(value) : std::nullopt)
      bounds = {std::max(bounds.first, kept->first), std::min(bounds.second, kept->second)};
    return bounds;
  }

  // `x pred y` held, or did not.
  void compare(arith::CmpIPredicate predicate, Value x, Value y, bool holds) {
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

  // The condition `condition` (an i1) held, or did not.
  void assume(Value condition, bool holds) {
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

  // `value` was each of `literals` (a case taken), or none of them (the
  // default taken).
  void assumeCase(Value value, ArrayRef<APInt> literals, bool isOne) {
    if (!admissible(value))
      return;
    Value condition;
    int64_t whenTrue = 1;
    if (value.getType().isInteger(1)) {
      condition = value;
    } else if (auto ext = value.getDefiningOp<arith::ExtUIOp>(); ext && ext.getIn().getType().isInteger(1)) {
      condition = ext.getIn();
    } else if (auto sext = value.getDefiningOp<arith::ExtSIOp>(); sext && sext.getIn().getType().isInteger(1)) {
      condition = sext.getIn();
      whenTrue = -1;
    }
    if (condition) {
      // Of the two values a condition stands for, those the case allows.
      // An i1 literal is the condition itself, true as 1.
      auto allowed = [&](int64_t v) {
        bool listed = llvm::any_of(literals, [&](const APInt &k) {
          return (k.getBitWidth() == 1 ? int64_t(k.getZExtValue()) : k.getSExtValue()) == v;
        });
        return isOne ? listed : !listed;
      };
      bool t = allowed(whenTrue), f = allowed(0);
      if (!t && !f)
        impossible();
      else if (t != f)
        assume(condition, t);
      return;
    }
    if (!isColumn(value))
      return;
    if (isOne) {
      zero(of(value) - Linear::constantOf(DynamicAPInt(literals.front().getSExtValue())));
      return;
    }
    // None of the literals: the range loses each at its ends.
    std::optional<Bounds> bounds = rangeOf(value);
    if (!bounds)
      return;
    auto [lo, hi] = *bounds;
    auto listed = [&](const DynamicAPInt &v) {
      return llvm::any_of(literals,
                          [&](const APInt &k) { return DynamicAPInt(k.getSExtValue()) == v; });
    };
    while (lo <= hi && listed(lo))
      ++lo;
    while (hi >= lo && listed(hi))
      --hi;
    if (lo > hi)
      return impossible();
    within(of(value), lo, hi);
  }

  // An access of `array` at `index` ran: the index is within it.
  void accessed(Value array, Value index) {
    if (!isColumn(index))
      return;
    Linear i = of(index);
    atLeastZero(i);
    atLeastZero((lengthOf(array) - i).plus(-1));
  }

  // The arrays with length columns.
  SmallVector<Value> roots() const {
    SmallVector<std::pair<unsigned, Value>> sorted;
    for (auto [root, column] : lengths)
      sorted.push_back({column, root});
    llvm::sort(sorted, [](const auto &a, const auto &b) { return a.first < b.first; });
    SmallVector<Value> out;
    for (auto &entry : sorted)
      out.push_back(entry.second);
    return out;
  }

  // The array `array` has `max(size, 0)` elements: its length is the
  // larger of the two, and equal to one, which a witness z in [0, 1]
  // chooses (no length or size reaches 2^63).
  void lengthIs(Value size, Value array) { zero(lengthOf(array) - clamped(size)); }

  // Whether `max(a, 0)` and `max(b, 0)` are the same integer.
  bool sameClamp(Value a, Value b) {
    if (!a.getType().isInteger(64) || !b.getType().isInteger(64))
      return false;
    return emptyWith((clamped(a) - clamped(b)).plus(-1)) && emptyWith((clamped(b) - clamped(a)).plus(-1));
  }

  // The values with columns, in the order they got them.
  SmallVector<Value> values() const {
    SmallVector<std::pair<unsigned, Value>> sorted;
    for (auto [value, column] : columns)
      sorted.push_back({column, value});
    llvm::sort(sorted, [](const auto &a, const auto &b) { return a.first < b.first; });
    SmallVector<Value> out;
    for (auto &entry : sorted)
      out.push_back(entry.second);
    return out;
  }

  // Whether no integers satisfy every constraint and `extra >= 0`.
  bool emptyWith(const Linear &extra) const {
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

private:
  struct Row {
    Linear e;
    bool equality;
  };

  // `max(value, 0)`, below 2^63: a length.
  Linear clamped(Value value) {
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
  Linear unsignedOf(Value x, unsigned width) {
    DynamicAPInt wrap = power(width);
    Linear u = fresh(DynamicAPInt(0), wrap - DynamicAPInt(1));
    Linear b = fresh(DynamicAPInt(0), DynamicAPInt(1));
    zero(u - of(x) - Linear().plus(b, wrap));
    return u;
  }

  // `v` is `e` wrapped to `width` bits: e - 2^width k for k in [-bound, bound].
  void wrapped(const Linear &v, Linear e, unsigned width, bool noWrap, int64_t bound) {
    if (!noWrap)
      e.plus(fresh(DynamicAPInt(-bound), DynamicAPInt(bound)), -power(width));
    zero(v - e);
  }

  void define(Value value, const Linear &v) {
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
    if (auto cast = dyn_cast<arith::IndexCastOp>(def); cast && cast.getIn().getType().isIndex() &&
                                                      value.getType().isInteger(64))
      return zero(v - of(cast.getIn()));
    if (auto dim = dyn_cast<memref::DimOp>(def))
      return defineDim(dim, v);
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

  // An array's one dimension is its length.
  void defineDim(memref::DimOp dim, const Linear &v) {
    std::optional<int64_t> index = dim.getConstantIndex();
    if (index && *index == 0 && isArray(dim.getSource().getType()))
      zero(v - lengthOf(dim.getSource()));
  }

  DataFlowSolver &solver;
  std::function<bool(Value)> admissible;
  CarriedBounds carried;
  DenseMap<Value, unsigned> columns;
  DenseMap<Value, unsigned> lengths;
  SmallVector<Row> rows;
  unsigned count = 0;
  unsigned definitions = 0;
};

} // namespace idr::inbounds
