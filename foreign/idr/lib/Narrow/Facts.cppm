// idr.narrow:facts: the bounds of values, as the analysis found them and as
// the pass makes them, and the words and bigs that stand for each other.
export module idr.narrow:facts;

import idr.mlir;
import idr.dialect;
import idr.ownership;
import idr.ranges;

import :naturals;

using namespace mlir;
using namespace mlir::dataflow;

namespace idr::narrow {

using ranges::Bounds;

bool isBig(Type type) { return isa<BigType, NatType>(unrestricted(type)); }

// Whether the big `value` holds a reference of its own, which a word
// taking its place in a consuming use leaves it to drop: once counting ran
// (`counted`), its grade says so, and a value that stands for one (a
// small big, poison) holds none.
bool ownedBig(Value value, bool counted) {
  return counted && isOwned(value.getType()) && !ownership::isStatic(value);
}

// The bounds of values: the analysis's, and those of the values the pass
// makes, which stand for values it analysed.
class Facts {
public:
  Facts(DataFlowSolver &s, bool counted) : solver(s), counted(counted) {}

  bool owned(Value value) const { return ownedBig(value, counted); }

  // Whether `value` is borrowed once counting ran: it is counted, and holds
  // no reference of its own.
  bool borrowed(Value value) const {
    return counted && !isOwned(value.getType()) && !ownership::isStatic(value);
  }

  Bounds of(Value value) const {
    // The program's poison may be taken to be any value, so a small one.
    if (value.getDefiningOp<ub::PoisonOp>())
      return {0, 0};
    if (auto it = made.find(value); it != made.end())
      return it->second;
    // Code the analysis never reached has no range, and proves nothing.
    std::optional<ConstantIntRanges> range = rangeOf(solver, value);
    if (!range)
      return {};
    Bounds bounds = ranges::boundsOf(*range);
    if (isa<NatType>(value.getType()) && bounds.hi && (!bounds.lo || *bounds.lo < 0))
      bounds.lo = 0;
    return bounds;
  }

  bool fits(Value value) const { return isBig(value.getType()) && of(value).fits(); }

  // Nothing among `values` is negative.
  bool nonNegative(ValueRange values) const {
    return llvm::all_of(values, [&](Value v) {
      Bounds b = of(v);
      return b.lo && *b.lo >= 0;
    });
  }

  // The word of the big `value`: the integer it was made of, when it was,
  // or its value converted.
  Value word(OpBuilder &b, Location loc, Value value) {
    auto i64 = b.getI64Type();
    if (auto poison = value.getDefiningOp<ub::PoisonOp>()) {
      // The word of the program's poison is poison: no conversion runs on
      // a path that never reads it. The big poison goes once nothing reads
      // it.
      converted_.push_back(poison);
      return ub::PoisonOp::create(b, loc, i64);
    }
    if (auto small = value.getDefiningOp<BigSmallOp>())
      return small.getValue();
    if (auto from = value.getDefiningOp<BigFromIntOp>()) {
      Value source = from.getValue();
      if (source.getType() == i64)
        return source;
      return from.getIsSigned() ? Value(arith::ExtSIOp::create(b, loc, i64, source))
                                : Value(arith::ExtUIOp::create(b, loc, i64, source));
    }
    Value converted = BigToIntOp::create(b, loc, i64, value);
    converted_.push_back(converted.getDefiningOp());
    return converted;
  }

  // The big of type `type` whose value is `word`, with the bounds `bounds`,
  // which prove it small: it holds no reference, so counting skips it.
  Value big(OpBuilder &b, Location loc, Type type, Value word, Bounds bounds) {
    Value value = BigSmallOp::create(b, loc, type, word);
    made[value] = bounds;
    converted_.push_back(value.getDefiningOp());
    return value;
  }

  // The conversions made, for the folds that pair them.
  ArrayRef<Operation *> converted() const { return converted_; }

private:
  DataFlowSolver &solver;
  bool counted;
  DenseMap<Value, Bounds> made;
  SmallVector<Operation *> converted_;
};

} // namespace idr::narrow
