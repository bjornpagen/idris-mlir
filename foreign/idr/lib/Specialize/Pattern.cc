// Patterns: taking a value's shape, keying it and rebuilding it.

#include "Specialize/Pattern.h"

#include "mlir/IR/Matchers.h"

#include "llvm/ADT/SetVector.h"

using namespace mlir;

namespace idr::specialize {

namespace {

template <typename... Cases> struct Match : Cases... {
  using Cases::operator()...;
};

// A constant that stands for a value: poison stands for none, and erased is
// not constant.
bool constant(Value value, Attribute &out) {
  return !isa<ErasedType>(value.getType()) && matchPattern(value, m_Constant(&out)) &&
         !isa<ub::PoisonAttrInterface>(out);
}

LocationAttr builtAt(Value value) {
  Operation *def = value.getDefiningOp();
  return def ? LocationAttr(def->getLoc()) : LocationAttr(value.getLoc());
}

// A chain of clones counts a big down by one at a time; past this it is
// too long to unroll anyway, so the exact count does not matter.
constexpr uint64_t countless = uint64_t(1) << 32;

// The size of `value` as a tree, up to countless. A constant that
// compile-time evaluation made shares its parts, so each part is measured
// once, in `sizes`, however often it occurs.
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
  if (auto con = dyn_cast<ConAttr>(value)) {
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

// A constant as a key: constructors and closures as the nodes they fold
// from. Each shared part is keyed once, in `keys`.
Attribute keyOfConstant(Attribute value, llvm::DenseMap<Attribute, Attribute> &keys) {
  if (Attribute known = keys.lookup(value))
    return known;
  MLIRContext *ctx = value.getContext();
  auto keysOf = [&](ArrayAttr parts) {
    return ArrayAttr::get(ctx, llvm::map_to_vector(parts, [&](Attribute part) {
                            return keyOfConstant(part, keys);
                          }));
  };
  Attribute key = value;
  if (auto con = dyn_cast<ConAttr>(value))
    key = KeyConAttr::get(ctx, con.getCtor().getRootReference(), con.getCtor().getLeafReference(),
                          keysOf(con.getFields()));
  else if (auto closure = dyn_cast<ClosureAttr>(value))
    key = KeyClosureAttr::get(ctx, closure.getCallee().getAttr(), keysOf(closure.getCaptures()));
  return keys[value] = key;
}

Attribute keyOfConstant(Attribute value) {
  llvm::DenseMap<Attribute, Attribute> keys;
  return keyOfConstant(value, keys);
}

std::vector<Pattern> shapesOf(ValueRange values, SmallVectorImpl<Value> &leaves) {
  std::vector<Pattern> out;
  for (Value value : values)
    out.push_back(shapeOf(value, leaves));
  return out;
}

ArrayAttr keysOf(MLIRContext *ctx, const std::vector<Pattern> &parts) {
  return ArrayAttr::get(ctx, llvm::map_to_vector(parts, keyOf));
}

} // namespace

Pattern leafOf(Value value, unsigned index) {
  return {Hole{index}, value.getType(), builtAt(value)};
}

Pattern shapeOf(Value value, SmallVectorImpl<Value> &leaves) {
  Attribute known;
  if (constant(value, known))
    return {Constant{known}, value.getType(), builtAt(value)};
  if (auto con = value.getDefiningOp<ConOp>())
    return {Con{con.getCtorAttr(), shapesOf(con.getFields(), leaves)}, value.getType(),
            builtAt(value)};
  if (auto closure = value.getDefiningOp<ClosureOp>())
    return {Closure{closure.getCalleeAttr(), shapesOf(closure.getCaptures(), leaves)},
            value.getType(), builtAt(value)};
  if (auto enter = value.getDefiningOp<LinEnterOp>()) {
    Pattern inner = shapeOf(enter.getValue(), leaves);
    if (!inner.isHole())
      return {Linear{{std::move(inner)}}, value.getType(), builtAt(value)};
    // A leaf that entered is a leaf itself: the entry stays with the caller.
    leaves.pop_back();
  }
  leaves.push_back(value);
  return leafOf(value, static_cast<unsigned>(leaves.size() - 1));
}

void eraseUnused(ArrayRef<Value> values) {
  auto shapeOp = [](Value value) -> Operation * {
    Operation *def = value.getDefiningOp();
    return isa_and_nonnull<ConOp, ClosureOp, LinEnterOp>(def) ? def : nullptr;
  };
  // The operations, not the values: a value passed twice names one
  // operation, which is erased once.
  llvm::SetVector<Operation *> candidates;
  for (Value value : values)
    if (Operation *def = shapeOp(value))
      candidates.insert(def);
  while (!candidates.empty()) {
    Operation *op = candidates.pop_back_val();
    if (!op->use_empty())
      continue;
    for (Value part : op->getOperands())
      if (Operation *def = shapeOp(part))
        candidates.insert(def);
    op->erase();
  }
}

bool usedOnce(Value value) {
  Operation *def = value.getDefiningOp();
  if (!isa_and_nonnull<ConOp, ClosureOp, LinEnterOp>(def))
    return true;
  return value.hasOneUse() && llvm::all_of(def->getOperands(), usedOnce);
}

bool isClosed(Value value) {
  if (matchPattern(value, m_Constant()))
    return true;
  Operation *def = value.getDefiningOp();
  return isa_and_nonnull<ConOp, ClosureOp>(def) && llvm::all_of(def->getOperands(), isClosed);
}

bool hasStructure(const Pattern &pattern) {
  return std::visit(Match{[](const Hole &) { return false; },
                          [](const Constant &c) { return isa<ConAttr, ClosureAttr>(c.value); },
                          [](const Con &) { return true; }, [](const Closure &) { return true; },
                          [](const Linear &l) { return hasStructure(l.value.front()); }},
                    pattern.node);
}

void renumber(Pattern &pattern, unsigned &next) {
  std::visit(Match{[&](Hole &hole) { hole.index = next++; }, [](Constant &) {},
                   [&](Con &con) {
                     for (Pattern &field : con.fields)
                       renumber(field, next);
                   },
                   [&](Closure &closure) {
                     for (Pattern &capture : closure.captures)
                       renumber(capture, next);
                   },
                   [&](Linear &linear) { renumber(linear.value.front(), next); }},
             pattern.node);
}

namespace {

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

Attribute keyOf(const Pattern &pattern) {
  MLIRContext *ctx = pattern.type.getContext();
  return std::visit(
      Match{[&](const Hole &hole) -> Attribute { return KeyHoleAttr::get(ctx, hole.index); },
            [](const Constant &c) { return keyOfConstant(c.value); },
            [&](const Con &con) -> Attribute {
              return KeyConAttr::get(ctx, con.ctor.getRootReference(),
                                     con.ctor.getLeafReference(), keysOf(ctx, con.fields));
            },
            [&](const Closure &closure) -> Attribute {
              return KeyClosureAttr::get(ctx, closure.callee.getAttr(),
                                         keysOf(ctx, closure.captures));
            },
            // The type of the position says the value is linear.
            [](const Linear &linear) { return keyOf(linear.value.front()); }},
      pattern.node);
}

Value rebuild(OpBuilder &b, const Pattern &pattern, ArrayRef<Value> holes) {
  Location loc(pattern.loc);
  auto rebuildAll = [&](const std::vector<Pattern> &parts) {
    SmallVector<Value> values;
    for (const Pattern &part : parts)
      values.push_back(rebuild(b, part, holes));
    return values;
  };
  return std::visit(
      Match{[&](const Hole &hole) { return holes[hole.index]; },
            [&](const Constant &c) -> Value {
              // shapeOf() took the constant from a constant op of this type.
              Dialect *idr = b.getContext()->getLoadedDialect<IdrDialect>();
              return idr->materializeConstant(b, c.value, pattern.type, loc)->getResult(0);
            },
            [&](const Con &con) -> Value {
              return ConOp::create(b, loc, pattern.type, con.ctor, rebuildAll(con.fields));
            },
            [&](const Closure &closure) -> Value {
              return ClosureOp::create(b, loc, pattern.type, closure.callee,
                                       rebuildAll(closure.captures));
            },
            [&](const Linear &linear) -> Value {
              return LinEnterOp::create(b, loc, pattern.type,
                                        rebuild(b, linear.value.front(), holes));
            }},
      pattern.node);
}

void labels(const Pattern &pattern, SmallVectorImpl<FlatSymbolRefAttr> &out) {
  std::visit(Match{[](const Hole &) {},
                   [&](const Constant &c) {
                     Attribute(c.value).walk(
                         [&](ClosureAttr closure) { out.push_back(closure.getCallee()); });
                   },
                   [&](const Con &con) {
                     for (const Pattern &field : con.fields)
                       labels(field, out);
                   },
                   [&](const Closure &closure) {
                     out.push_back(closure.callee);
                     for (const Pattern &capture : closure.captures)
                       labels(capture, out);
                   },
                   [&](const Linear &linear) { labels(linear.value.front(), out); }},
             pattern.node);
}

} // namespace idr::specialize
