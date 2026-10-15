// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Patterns: taking a value's shape, what a key asks of a shape, rebuilding
// the value a key's pattern stands for, and erasing a shape a call no
// longer reads.
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Symbols.h"
#include "idr/Support/Worklist.h"
#include "idr/Transforms/Specialize.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/IR/Matchers.h"
#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/STLExtras.h"

#include <optional>

using namespace mlir;

namespace idr::specialize::detail {

namespace {

// A constant the node builds again as it was built here: the value of an
// op the dialect materializes, as rebuild does.
bool constant(Value value, Attribute &out) {
  return isa_and_nonnull<ConstantOp, arith::ConstantOp>(value.getDefiningOp()) &&
         matchPattern(value, m_Constant(&out));
}

// The constructor that builds `value` whole: an idr.con with every field
// given. One with holes leaves fields to be written through its
// destinations, after it, so what it builds is not known where it is.
ConOp builtBy(Value value) {
  auto con = value.getDefiningOp<ConOp>();
  return con && con.getHoles().empty() ? con : ConOp();
}

// Whether `op` builds part of a shape, which the node's call takes apart.
bool isShapeOp(Operation *op) {
  if (auto con = dyn_cast_if_present<ConOp>(op))
    return con.getHoles().empty();
  return isa_and_nonnull<LinEnterOp>(op);
}

// The field types of constructor `tag` of the data type a value of `type`
// is of.
ArrayRef<Type> fieldTypes(Type type, Tag tag) {
  return dataTypeOf(type).getCtor(tag).fields;
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
  if (ConOp con = builtBy(value))
    return {Con{con.getTag(), shapesOf(con.getFields())}, value.getType()};
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
  std::visit(llvm::makeVisitor([&](Hole &hole) { hole.index = next++; }, [](Constant &) {},
                               [&](Con &con) {
                                 for (Pattern &field : con.fields)
                                   renumber(field, next);
                               },
                               [&](Linear &linear) { renumber(linear.value.front(), next); }),
             pattern.node);
}

// Whether `pattern` has structure: a constructor, as a node or as a
// constant. A lone scalar is none: a number specialized on would make a
// node per value, where LLVM weighs constant arguments better.
bool hasStructure(const Pattern &pattern) {
  return std::visit(llvm::makeVisitor([](const Hole &) { return false; },
                                      [](const Constant &c) { return isa<ConAttr>(c.value); },
                                      [](const Con &) { return true; },
                                      [](const Linear &l) { return hasStructure(l.value.front()); }),
                    pattern.node);
}

// Whether `value` is closed: a constant, or a constructor of closed values.
bool isClosed(Value value) {
  if (matchPattern(value, m_Constant()))
    return true;
  ConOp con = builtBy(value);
  return con && llvm::all_of(con.getFields(), isClosed);
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
// a linear leaf used by both would be used twice. An operation enters the
// worklist when it has no use left, which happens once, since erasing
// only takes uses away; a value passed twice names one operation, erased
// once.
void eraseUnused(RewriterBase &rewriter, ArrayRef<Value> values) {
  OnceWorklist<Operation *> dead;
  auto consider = [&](Value value) {
    if (Operation *def = value.getDefiningOp(); isShapeOp(def) && def->use_empty())
      dead.push(def);
  };
  llvm::for_each(values, consider);
  while (std::optional<Operation *> op = dead.pop()) {
    SmallVector<Value> operands((*op)->getOperands());
    rewriter.eraseOp(*op);
    llvm::for_each(operands, consider);
  }
}

// A key's pattern rebuilt at a position of `type`: a hole is the parameter
// that holds it, a linear position enters what is rebuilt inside it, a
// constructor is built over its fields at their declared types, and a
// constant is the one the dialect materializes.
Value rebuild(OpBuilder &b, Location loc, Attribute pattern, Type type, ArrayRef<Value> holes) {
  if (auto hole = dyn_cast<KeyHoleAttr>(pattern))
    return holes[hole.getIndex()];
  if (isLinearPosition(type))
    return LinEnterOp::create(b, loc, type, rebuild(b, loc, pattern, unrestricted(type), holes));
  if (auto con = dyn_cast<KeyConAttr>(pattern)) {
    ArrayRef<Type> types = fieldTypes(type, con.getTag());
    SmallVector<Value> fields;
    for (auto [field, fieldType] : llvm::zip_equal(con.getFields(), types))
      fields.push_back(rebuild(b, loc, field, fieldType, holes));
    return ConOp::create(b, loc, type, con.getTag(), fields).getResult();
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
  ArrayRef<Type> types = fieldTypes(unrestricted(type), con.getTag());
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
