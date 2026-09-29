// Patterns: taking a value's shape, keying it and rebuilding it.

#include "Specialize/Pattern.h"

#include "mlir/IR/Matchers.h"

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

uint64_t constantSize(Attribute value) {
  // A chain of clones counts a big down by one at a time; past this it is
  // too long to unroll anyway, so the exact count does not matter.
  constexpr uint64_t countless = uint64_t(1) << 32;
  auto sum = [](ArrayAttr parts) {
    uint64_t size = 1;
    for (Attribute part : parts)
      size += constantSize(part);
    return size;
  };
  if (auto con = dyn_cast<ConAttr>(value))
    return sum(con.getFields());
  if (auto closure = dyn_cast<ClosureAttr>(value))
    return sum(closure.getCaptures());
  if (auto big = dyn_cast<BigAttr>(value)) {
    StringRef digits = big.getValue();
    digits.consume_front("-");
    uint64_t n = 0;
    return digits.size() > 9 || digits.getAsInteger(10, n) ? countless : n;
  }
  return 0;
}

// A constant as a key: constructors and closures as the nodes they fold
// from.
Attribute keyOfConstant(Attribute value) {
  MLIRContext *ctx = value.getContext();
  auto keys = [&](ArrayAttr parts) {
    return ArrayAttr::get(ctx, llvm::map_to_vector(parts, keyOfConstant));
  };
  if (auto con = dyn_cast<ConAttr>(value))
    return KeyConAttr::get(ctx, con.getCtor().getRootReference(), con.getCtor().getLeafReference(),
                           keys(con.getFields()));
  if (auto closure = dyn_cast<ClosureAttr>(value))
    return KeyClosureAttr::get(ctx, closure.getCallee().getAttr(), keys(closure.getCaptures()));
  return value;
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

void eraseUnused(Value value) {
  Operation *def = value.getDefiningOp();
  if (!isa_and_nonnull<ConOp, ClosureOp, LinEnterOp>(def) || !def->use_empty())
    return;
  SmallVector<Value> parts(def->getOperands());
  def->erase();
  for (Value part : parts)
    eraseUnused(part);
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

uint64_t unrollSize(const Pattern &pattern) {
  auto sum = [](const std::vector<Pattern> &parts) {
    uint64_t size = 1;
    for (const Pattern &part : parts)
      size += unrollSize(part);
    return size;
  };
  return std::visit(Match{[](const Hole &) { return uint64_t(0); },
                          [](const Constant &c) { return constantSize(c.value); },
                          [&](const Con &con) { return sum(con.fields); },
                          [&](const Closure &closure) { return sum(closure.captures); },
                          [](const Linear &linear) { return unrollSize(linear.value.front()); }},
                    pattern.node);
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
