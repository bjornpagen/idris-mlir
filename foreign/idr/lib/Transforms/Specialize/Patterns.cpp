// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Patterns: taking a value's shape, rebuilding the value a shape stands
// for, what a key asks of a shape, and erasing a shape a call no longer
// reads.
#include "idr/IR/IdrDialect.h"
#include "idr/Analysis/Specialize.h"
#include "idr/Transforms/Specialize.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/IR/Matchers.h"
#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SetVector.h"

using namespace mlir;

namespace idr::specialize {

namespace {

// A constant the clone builds again as it was built here: the value of an
// op the dialect materializes, as rebuild does.
bool constant(Value value, Attribute &out) {
  return isa_and_nonnull<ConstantOp, arith::ConstantOp>(value.getDefiningOp()) &&
         matchPattern(value, m_Constant(&out));
}

// A chain of clones counts a big down by one at a time; past this it is
// too long to unroll anyway, so the exact count does not matter.
constexpr uint64_t countless = uint64_t(1) << 32;

// The size of `value` as a tree, up to countless. A constant shares its
// parts, so each part is measured once, in `sizes`, however often it
// occurs. A run measures as the constructors it stands for, each cell read
// once: its tail, and each cell one with its fields.
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

// Whether `op` builds part of a shape, which the clone's call takes apart.
bool isShapeOp(Operation *op) { return isa_and_nonnull<ConOp, ClosureOp, LinEnterOp>(op); }

// Where `value` was built, which the ops that rebuild it report: its
// defining op, or the value itself.
LocationAttr builtAt(Value value) {
  Operation *def = value.getDefiningOp();
  return def ? LocationAttr(def->getLoc()) : LocationAttr(value.getLoc());
}

} // namespace

// The leaf `value` as hole `index`.
Pattern leafOf(Value value, unsigned index) {
  return {Hole{index}, value.getType(), builtAt(value)};
}

// The pattern of `value`: its runtime leaves are appended to `leaves`, and
// its holes numbered from the size `leaves` had. A constant the clone would
// not build again is a leaf, as is a linear value, whose shape its one use
// keeps.
Pattern shapeOf(Value value, SmallVectorImpl<Value> &leaves) {
  auto shapesOf = [&](ValueRange values) {
    std::vector<Pattern> out;
    for (Value part : values)
      out.push_back(shapeOf(part, leaves));
    return out;
  };
  Attribute known;
  if (constant(value, known))
    return {Constant{known}, value.getType(), builtAt(value)};
  if (auto con = value.getDefiningOp<ConOp>())
    return {Con{con.getCtorAttr(), shapesOf(con.getFields())}, value.getType(), builtAt(value)};
  if (auto closure = value.getDefiningOp<ClosureOp>())
    return {Closure{closure.getCalleeAttr(), shapesOf(closure.getCaptures())}, value.getType(),
            builtAt(value)};
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

// The value `pattern` stands for, rebuilt at `b`, each hole taken from
// `holes` by its number.
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

// `pattern` with its holes numbered from `next`, which advances past them.
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

// The functions `pattern` names as closure labels.
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

// Whether `pattern` has structure: a constructor or a closure, as a node
// or as a constant. A lone scalar is none: a number specialized on would
// make a clone per value, where LLVM weighs constant arguments better.
bool hasStructure(const Pattern &pattern) {
  return std::visit(Match{[](const Hole &) { return false; },
                          [](const Constant &c) { return isa<ConAttr, ClosureAttr>(c.value); },
                          [](const Con &) { return true; }, [](const Closure &) { return true; },
                          [](const Linear &l) { return hasStructure(l.value.front()); }},
                    pattern.node);
}

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
      return n.isNegative() || n.getActiveBits() > 32 ? countless : n.getZExtValue();
    }
  return sizeOf(pattern);
}

// Whether `value` is closed: a constant, or a constructor or closure of
// closed values.
bool isClosed(Value value) {
  if (matchPattern(value, m_Constant()))
    return true;
  Operation *def = value.getDefiningOp();
  return isa_and_nonnull<ConOp, ClosureOp>(def) && llvm::all_of(def->getOperands(), isClosed);
}

// Whether the shape of `value` has no use but the one that reads it: each
// operation that built it is used once. A call on such a shape takes its
// leaves alone once the shape is erased.
bool usedOnce(Value value) {
  Operation *def = value.getDefiningOp();
  if (!isShapeOp(def))
    return true;
  return value.hasOneUse() && llvm::all_of(def->getOperands(), usedOnce);
}

// Erases the operations that built the shapes of `values` once nothing
// uses them. They hold the leaves, which the clone's call now takes itself:
// a linear leaf used by both would be used twice. The set holds operations,
// not values: a value passed twice names one operation, erased once.
void eraseUnused(RewriterBase &rewriter, ArrayRef<Value> values) {
  llvm::SetVector<Operation *> candidates;
  auto consider = [&](Value value) {
    if (Operation *def = value.getDefiningOp(); isShapeOp(def))
      candidates.insert(def);
  };
  llvm::for_each(values, consider);
  while (!candidates.empty()) {
    Operation *op = candidates.pop_back_val();
    if (!op->use_empty())
      continue;
    llvm::for_each(op->getOperands(), consider);
    rewriter.eraseOp(op);
  }
}

} // namespace idr::specialize
