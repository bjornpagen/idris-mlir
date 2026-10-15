// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Patterns: taking a value's shape, what a key asks of a shape, rebuilding
// the value a key's pattern stands for, and erasing a shape a call no
// longer reads.
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Symbols.h"
#include "idr/Transforms/Specialize.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/IR/Matchers.h"
#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SetVector.h"

using namespace mlir;

namespace idr::specialize::detail {

namespace {

// A constant the node builds again as it was built here: the value of an
// op the dialect materializes, as rebuild does.
bool constant(Value value, Attribute &out) {
  return isa_and_nonnull<ConstantOp, arith::ConstantOp>(value.getDefiningOp()) &&
         matchPattern(value, m_Constant(&out));
}

// A chain of nodes counts a big down by one at a time; past this it is too
// long to unroll anyway, so the exact count does not matter.
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
                          [](const Linear &linear) { return sizeOf(linear.value.front()); }},
                    pattern.node);
}

// Whether `op` builds part of a shape, which the node's call takes apart.
bool isShapeOp(Operation *op) { return isa_and_nonnull<ConOp, LinEnterOp>(op); }

// The field types of constructor `ctor` of the data type a value of `type`
// is of.
ArrayRef<Type> fieldTypes(Type type, StringAttr ctor) {
  DataType data = dataTypeOf(type);
  std::optional<unsigned> tag = data ? data.getTag(ctor.getValue()) : std::nullopt;
  return tag ? data.getCtor(*tag).fields : ArrayRef<Type>();
}

// Whether a position of `type` is linear: a value there entered a linear
// type, which a rebuilt value enters again.
bool isLinearPosition(Type type) { return unrestricted(type) != type; }

} // namespace

// The leaf `value` as hole `index`.
Pattern leafOf(Value value, unsigned index) { return {Hole{index}, value.getType()}; }

// The pattern of `value`: its runtime leaves are appended to `leaves`, and
// its holes numbered from the size `leaves` had. A constant the node would
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
    return {Constant{known}, value.getType()};
  if (auto con = value.getDefiningOp<ConOp>())
    return {Con{con.getCtorAttr(), shapesOf(con.getFields())}, value.getType()};
  if (auto enter = value.getDefiningOp<LinEnterOp>()) {
    Pattern inner = shapeOf(enter.getValue(), leaves);
    if (!inner.isHole())
      return {Linear{{std::move(inner)}}, value.getType()};
    // A leaf that entered is a leaf itself: the entry stays with the caller.
    leaves.pop_back();
  }
  leaves.push_back(value);
  return leafOf(value, static_cast<unsigned>(leaves.size() - 1));
}

// `pattern` with its holes numbered from `next`, which advances past them.
void renumber(Pattern &pattern, unsigned &next) {
  std::visit(Match{[&](Hole &hole) { hole.index = next++; }, [](Constant &) {},
                   [&](Con &con) {
                     for (Pattern &field : con.fields)
                       renumber(field, next);
                   },
                   [&](Linear &linear) { renumber(linear.value.front(), next); }},
             pattern.node);
}

// Whether `pattern` has structure: a constructor, as a node or as a
// constant. A lone scalar is none: a number specialized on would make a
// node per value, where LLVM weighs constant arguments better.
bool hasStructure(const Pattern &pattern) {
  return std::visit(Match{[](const Hole &) { return false; },
                          [](const Constant &c) { return isa<ConAttr>(c.value); },
                          [](const Con &) { return true; },
                          [](const Linear &l) { return hasStructure(l.value.front()); }},
                    pattern.node);
}

// How long a chain of nodes that each take a proper part of the value can
// be: its constructors, the value of a big, which counts down by one, and a
// lone machine integer, a counter; a negative one has no end. Scalars
// inside a structure take no part apart.
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

// Whether `value` is closed: a constant, or a constructor of closed values.
bool isClosed(Value value) {
  if (matchPattern(value, m_Constant()))
    return true;
  Operation *def = value.getDefiningOp();
  return isa_and_nonnull<ConOp>(def) && llvm::all_of(def->getOperands(), isClosed);
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
// uses them. They hold the leaves, which the node's call now takes itself:
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

// A key's pattern rebuilt at a position of `type`: a hole is the parameter
// that holds it, a linear position enters what is rebuilt inside it, a
// constructor is built over its fields at their declared types, and a
// scalar is the constant the dialect materializes.
Value rebuild(OpBuilder &b, Location loc, Attribute pattern, Type type, ArrayRef<Value> holes) {
  if (auto hole = dyn_cast<KeyHoleAttr>(pattern))
    return holes[hole.getIndex()];
  if (isLinearPosition(type))
    return LinEnterOp::create(b, loc, type, rebuild(b, loc, pattern, unrestricted(type), holes));
  if (auto con = dyn_cast<KeyConAttr>(pattern)) {
    ArrayRef<Type> types = fieldTypes(type, con.getCtor());
    SmallVector<Value> fields;
    for (auto [field, fieldType] : llvm::zip_equal(con.getFields(), types))
      fields.push_back(rebuild(b, loc, field, fieldType, holes));
    return ConOp::create(b, loc, type, FlatSymbolRefAttr::get(con.getCtor()), fields);
  }
  Dialect *idr = b.getContext()->getLoadedDialect<IdrDialect>();
  return idr->materializeConstant(b, pattern, type, loc)->getResult(0);
}

void holeTypes(Attribute pattern, Type type, SmallVectorImpl<Type> &out) {
  if (isa<KeyHoleAttr>(pattern)) {
    out.push_back(type);
    return;
  }
  auto con = dyn_cast<KeyConAttr>(pattern);
  if (!con)
    return;
  ArrayRef<Type> types = fieldTypes(unrestricted(type), con.getCtor());
  for (auto [field, fieldType] : llvm::zip_equal(con.getFields(), types))
    holeTypes(field, fieldType, out);
}

unsigned countHoles(Attribute pattern) {
  if (isa<KeyHoleAttr>(pattern))
    return 1;
  auto con = dyn_cast<KeyConAttr>(pattern);
  if (!con)
    return 0;
  unsigned holes = 0;
  for (Attribute field : con.getFields())
    holes += countHoles(field);
  return holes;
}

} // namespace idr::specialize::detail
