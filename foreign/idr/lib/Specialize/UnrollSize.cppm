// idr.specialize:unrollsize: how long a chain of clones on a pattern can
// be.
export module idr.specialize:unrollsize;

import idr.mlir;
import idr.dialect;

import :pattern;

using namespace mlir;

namespace idr::specialize {

namespace {

// A chain of clones counts a big down by one at a time; past this it is
// too long to unroll anyway, so the exact count does not matter.
constexpr uint64_t countless = uint64_t(1) << 32;

// The size of `value` as a tree, up to countless. A constant that
// compile-time evaluation made shares its parts, so each part is measured
// once, in `sizes`, however often it occurs. A run measures as the
// constructors it stands for, each cell read once: its tail, and each cell
// one with its fields.
uint64_t constantSize(Attribute value, llvm::DenseMap<Attribute, uint64_t> &sizes) {
  if (auto known = sizes.find(value); known != sizes.end())
    return known->second;
  auto sum = [&](ArrayAttr parts) {
    uint64_t size = 1;
    for (Attribute part : parts)
      size = std::min(countless, size + constantSize(part, sizes));
    return size;
  };
  uint64_t size = 0;
  if (auto con = dyn_cast<ConAttr>(value); con && con.isRun()) {
    size = constantSize(con.getTail(), sizes);
    for (ArrayAttr cell : con.getRunCells())
      size = std::min(countless, size + sum(cell));
  } else if (con) {
    size = sum(con.getFields());
  } else if (auto closure = dyn_cast<ClosureAttr>(value)) {
    size = sum(closure.getCaptures());
  } else if (auto big = dyn_cast<BigAttr>(value)) {
    StringRef digits = big.getValue();
    digits.consume_front("-");
    uint64_t n = 0;
    size = digits.size() > 9 || digits.getAsInteger(10, n) ? countless : n;
  }
  return sizes[value] = size;
}

uint64_t constantSize(Attribute value) {
  llvm::DenseMap<Attribute, uint64_t> sizes;
  return constantSize(value, sizes);
}

uint64_t sizeOf(const Pattern &pattern) {
  auto sum = [](const std::vector<Pattern> &parts) {
    uint64_t size = 1;
    for (const Pattern &part : parts)
      size += sizeOf(part);
    return size;
  };
  return std::visit(Match{[](const Hole &) { return uint64_t(0); },
                          [](const Constant &c) { return constantSize(c.value); },
                          [&](const Con &con) { return sum(con.fields); },
                          [&](const Closure &closure) { return sum(closure.captures); },
                          [](const Linear &linear) { return sizeOf(linear.value.front()); }},
                    pattern.node);
}

} // namespace

} // namespace idr::specialize

export namespace idr::specialize {

// How long a chain of clones that each take a proper part of the value can
// be: its constructors and closures, the value of a big, which counts down
// by one, and a lone machine integer, a counter; a negative one has no end.
// Scalars inside a structure take no part apart.
uint64_t unrollSize(const Pattern &pattern) {
  // A machine integer on its own is a counter, counted down to zero; one
  // below zero only goes on. Inside a structure it is an element.
  if (const auto *c = std::get_if<Constant>(&pattern.node))
    if (auto integer = dyn_cast<IntegerAttr>(c->value); integer && isa<IntegerType>(integer.getType())) {
      const APInt &n = integer.getValue();
      return n.isNegative() || n.getActiveBits() > 32 ? uint64_t(1) << 32 : n.getZExtValue();
    }
  return sizeOf(pattern);
}

} // namespace idr::specialize
