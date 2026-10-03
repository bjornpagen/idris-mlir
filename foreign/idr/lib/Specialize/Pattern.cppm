// idr.specialize:pattern: the static shape of a value: what is known of it
// where it is built, over the runtime leaves it holds.
//
// A pattern is a hole (a runtime leaf), a constant, or a constructor or
// closure over the patterns of its operands. A shape is taken once per
// argument of a call, with its leaves; the clone is rebuilt from the
// pattern alone, each hole standing for the parameter that holds its leaf,
// so that what the key says and what the clone computes cannot differ.
export module idr.specialize:pattern;

import idr.mlir;

using namespace mlir;

// What the partitions over patterns share.
namespace idr::specialize {

// The visitor of a pattern's node: one callable per case.
template <typename... Cases> struct Match : Cases... {
  using Cases::operator()...;
};

// Where `value` was built, which the ops that rebuild it report: its
// defining op, or the value itself.
LocationAttr builtAt(Value value) {
  Operation *def = value.getDefiningOp();
  return def ? LocationAttr(def->getLoc()) : LocationAttr(value.getLoc());
}

} // namespace idr::specialize

export namespace idr::specialize {

struct Pattern;

// A runtime leaf: which leaf of its key it is, counting the key's holes in
// order. How often the clone may use it is its type's to say: a leaf reached
// through a linear parameter, field or capture has a linear type.
struct Hole {
  unsigned index;
};

struct Constant {
  mlir::Attribute value;
};

struct Con {
  mlir::SymbolRefAttr ctor; // `@T::@C`
  std::vector<Pattern> fields;
};

struct Closure {
  mlir::FlatSymbolRefAttr callee;
  std::vector<Pattern> captures;
};

// A value entered into a linear type (`idr.lin.enter`): rebuilt, it enters
// again, so the clone keeps the quantity Idris proved.
struct Linear {
  // Exactly one: the pattern of the value that entered.
  std::vector<Pattern> value;
};

struct Pattern {
  std::variant<Hole, Constant, Con, Closure, Linear> node;
  mlir::Type type;
  // Where the value was built: the ops that rebuild it are reported there.
  mlir::LocationAttr loc;

  bool isHole() const { return std::holds_alternative<Hole>(node); }
};

// The leaf `value` as hole `index`.
Pattern leafOf(mlir::Value value, unsigned index) {
  return {Hole{index}, value.getType(), builtAt(value)};
}

} // namespace idr::specialize
