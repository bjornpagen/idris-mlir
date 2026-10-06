// idr.inbounds:linear: the linear expressions the constraints are made of,
// with unbounded integer coefficients, and the words the columns stand for.
export module idr.inbounds:linear;

import idr.mlir;

using namespace mlir;
using llvm::DynamicAPInt;

namespace idr::inbounds {

// sum(coefficient * column) + constant.
export struct Linear {
  SmallVector<std::pair<unsigned, DynamicAPInt>> terms;
  DynamicAPInt constant{0};

  static Linear of(unsigned column) {
    Linear e;
    e.terms.push_back({column, DynamicAPInt(1)});
    return e;
  }
  static Linear constantOf(const DynamicAPInt &k) {
    Linear e;
    e.constant = k;
    return e;
  }
  Linear &plus(const Linear &other, const DynamicAPInt &k) {
    for (const auto &[column, c] : other.terms)
      terms.push_back({column, c * k});
    constant += other.constant * k;
    return *this;
  }
  Linear &plus(int64_t k) {
    constant += k;
    return *this;
  }
};

export Linear operator-(Linear a, const Linear &b) { return a.plus(b, DynamicAPInt(-1)); }
export Linear operator+(Linear a, const Linear &b) { return a.plus(b, DynamicAPInt(1)); }

// 2^width.
export DynamicAPInt power(unsigned width) {
  DynamicAPInt p(1);
  for (unsigned i = 0; i < width; ++i)
    p *= 2;
  return p;
}

// The width of an integer the system has columns for; 0 for an index,
// whose width is the target's; none for anything else, i1 included, whose
// values are the branches' conditions.
export std::optional<unsigned> widthOf(Type type) {
  if (type.isIndex())
    return 0;
  if (auto integer = dyn_cast<IntegerType>(type); integer && integer.getWidth() > 1 &&
                                                  integer.getWidth() <= 64)
    return integer.getWidth();
  return std::nullopt;
}

export bool isColumn(Value value) { return widthOf(value.getType()).has_value(); }

} // namespace idr::inbounds
