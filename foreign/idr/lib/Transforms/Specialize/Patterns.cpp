// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Patterns: taking a value's shape as a key attribute, what a key asks of a
// shape, rebuilding the value a key's pattern stands for, and erasing a
// shape a call no longer reads.
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

// Whether `op` builds part of a shape, which the node's call takes apart:
// a constructor, which builds its value whole, or an entry into a linear
// type.
bool isShapeOp(Operation *op) { return isa_and_nonnull<ConOp, LinEnterOp>(op); }

// The field types of constructor `tag` of the data type a value of `type`
// is of.
ArrayRef<Type> fieldTypes(Type type, Tag tag) {
  return dataTypeOf(type).getCtor(tag).fields;
}

// Whether a position of `type` is linear: a value there entered a linear
// type, which a rebuilt value enters again.
bool isLinearPosition(Type type) { return unrestricted(type) != type; }

} // namespace

// A constant the node would not build again is a leaf, as is a linear
// value, whose shape its one use keeps. A constant is keyed as itself, a run
// as the run it is, so a key is as large as the code and the constants that
// make it; a constructor is its tag, not a symbol use, so a key keeps no
// function alive. A value entered into a linear type is keyed as the value:
// the type of its position says it is linear.
Attribute shapeOf(Value value, SmallVectorImpl<Value> &leaves) {
  MLIRContext *ctx = value.getContext();
  Attribute known;
  if (constant(value, known))
    return known;
  if (auto con = value.getDefiningOp<ConOp>()) {
    SmallVector<Attribute> fields =
        llvm::map_to_vector(con.getFields(), [&](Value field) { return shapeOf(field, leaves); });
    return KeyConAttr::get(ctx, con.getTag(), ArrayAttr::get(ctx, fields));
  }
  if (auto enter = value.getDefiningOp<LinEnterOp>()) {
    Attribute inner = shapeOf(enter.getValue(), leaves);
    if (!isa<KeyHoleAttr>(inner))
      return inner;
    // A leaf that entered is a leaf itself: the entry stays with the caller.
    leaves.pop_back();
  }
  leaves.push_back(value);
  return KeyHoleAttr::get(ctx);
}

bool hasStructure(Attribute pattern) { return isa<KeyConAttr, ConAttr>(pattern); }

// Whether `value` is closed: a constant, or a constructor of closed values.
bool isClosed(Value value) {
  if (matchPattern(value, m_Constant()))
    return true;
  auto con = value.getDefiningOp<ConOp>();
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

// A key's pattern rebuilt at a position of `type`: a hole is the next
// parameter, a linear position enters what is rebuilt inside it, a
// constructor is built over its fields at their declared types, and a
// constant is the one the dialect materializes.
Value rebuild(OpBuilder &b, Location loc, Attribute pattern, Type type, ArrayRef<Value> holes,
              unsigned &next) {
  if (isa<KeyHoleAttr>(pattern))
    return holes[next++];
  if (isLinearPosition(type))
    return LinEnterOp::create(b, loc, type,
                              rebuild(b, loc, pattern, unrestricted(type), holes, next));
  if (auto con = dyn_cast<KeyConAttr>(pattern)) {
    ArrayRef<Type> types = fieldTypes(type, con.getTag());
    SmallVector<Value> fields;
    for (auto [field, fieldType] : llvm::zip_equal(con.getFields(), types))
      fields.push_back(rebuild(b, loc, field, fieldType, holes, next));
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
