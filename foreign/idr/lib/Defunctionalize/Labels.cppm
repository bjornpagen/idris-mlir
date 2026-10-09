// idr.defunctionalize:labels: the lattice of the analysis, the set of
// labels (functions) a closure or a suspension may hold, or unknown, and the
// anchors values reach and are read from without an SSA edge: a field of a
// constructor, and the elements of the arrays of one element type.
export module idr.defunctionalize:labels;

import idr.mlir;

using namespace mlir;
using namespace mlir::dataflow;

namespace idr::defunctionalize {

bool byName(StringAttr a, StringAttr b) { return a.getValue() < b.getValue(); }

// The labels a value may hold, sorted by name; `unknown` is the top.
struct Labels {
  bool unknown = false;
  SmallVector<StringAttr> names;

  static Labels of(StringAttr name) {
    Labels out;
    out.names.push_back(name);
    return out;
  }

  static Labels top() {
    Labels out;
    out.unknown = true;
    return out;
  }

  static Labels join(const Labels &a, const Labels &b) {
    if (a.unknown || b.unknown)
      return top();
    Labels out;
    std::set_union(a.names.begin(), a.names.end(), b.names.begin(), b.names.end(),
                   std::back_inserter(out.names), byName);
    return out;
  }

  bool mayHold(StringAttr name) const { return unknown || llvm::is_contained(names, name); }

  bool operator==(const Labels &other) const {
    return unknown == other.unknown && names == other.names;
  }

  void print(raw_ostream &os) const {
    if (unknown) {
      os << "unknown";
      return;
    }
    os << "{";
    llvm::interleaveComma(names, os, [&](StringAttr name) { os << "@" << name.getValue(); });
    os << "}";
  }
};

struct LabelLattice : Lattice<Labels> {
  // Its identity, which MLIR's TypeID finds by this name.
  static TypeID resolveTypeID() {
    static SelfOwningTypeID id;
    return id;
  }
  using Lattice::Lattice;
};

// A field of a constructor: (data type, constructor, index).
struct FieldAnchor
    : GenericLatticeAnchorBase<FieldAnchor, std::tuple<StringAttr, StringAttr, unsigned>> {
  // Its identity, which MLIR's TypeID finds by this name.
  static TypeID resolveTypeID() {
    static SelfOwningTypeID id;
    return id;
  }
  using Base::Base;
  Location getLoc() const override { return UnknownLoc::get(std::get<0>(getValue()).getContext()); }
  void print(raw_ostream &os) const override {
    auto [data, ctor, index] = getValue();
    os << "@" << data.getValue() << "::@" << ctor.getValue() << "[" << index << "]";
  }
};

// The elements of every array whose element type is this one: an array has
// one slot, as a constructor has one per field, and its element type, not
// the array value, names it, since a value of the type may be any array.
struct ElementsAnchor : GenericLatticeAnchorBase<ElementsAnchor, Type> {
  // Its identity, which MLIR's TypeID finds by this name.
  static TypeID resolveTypeID() {
    static SelfOwningTypeID id;
    return id;
  }
  using Base::Base;
  Location getLoc() const override { return UnknownLoc::get(getValue().getContext()); }
  void print(raw_ostream &os) const override { os << "elements of " << getValue(); }
};

// The labels a field, or the elements of arrays, may hold.
struct FieldLabels : AnalysisState {
  // Its identity, which MLIR's TypeID finds by this name.
  static TypeID resolveTypeID() {
    static SelfOwningTypeID id;
    return id;
  }
  using AnalysisState::AnalysisState;

  ChangeResult join(const Labels &other) {
    Labels joined = Labels::join(value, other);
    if (joined == value)
      return ChangeResult::NoChange;
    value = joined;
    return ChangeResult::Change;
  }

  void print(raw_ostream &os) const override { value.print(os); }

  Labels value;
};

} // namespace idr::defunctionalize
