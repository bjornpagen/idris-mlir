// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The grades: a type at a grade, its spellings, what its grade says of how
// a value may be used and what it owns, and the values seen through the
// positions their grades put them in. Whether two accesses name one element
// is the arrays' unit's.

#include "idr/IR/IdrDialect.h"

using namespace mlir;
using namespace idr;

Grade idr::gradeOf(Type type) {
  auto q = dyn_cast<QType>(type);
  return q ? q.getGrade() : Grade{};
}

Type idr::graded(Grade grade, Type value) {
  if (auto q = dyn_cast<QType>(value))
    value = q.getValue();
  return grade.plain() ? value : QType::get(value.getContext(), grade, value);
}

Type idr::unrestricted(Type type) {
  auto q = dyn_cast<QType>(type);
  return q ? q.getValue() : type;
}

Type idr::linear(Type value) { return graded({Quantity::One, Permission::Plain}, value); }

Type idr::world(MLIRContext *ctx) {
  return graded({Quantity::One, Permission::Plain}, WorldType::get(ctx));
}

bool idr::isLinear(Type type) {
  return gradeOf(type).quantity == Quantity::One && !isWorld(type);
}

// The world is known by its carrier, graded or not: a carrier that a grade
// was stripped from (unrestricted) is still the value it is.
bool idr::isWorld(Type type) { return isa<WorldType>(unrestricted(type)); }

bool idr::isClosureType(Type type) { return isa<FnType>(unrestricted(type)); }

bool idr::isLazyType(Type type) { return isa<LazyType>(unrestricted(type)); }

bool idr::isOwned(Type type) {
  Permission permission = gradeOf(type).permission;
  return permission == Permission::Own || permission == Permission::Excl;
}

Type idr::owned(Type type) {
  Grade grade = gradeOf(type);
  if (grade.permission == Permission::Plain)
    grade.permission = Permission::Own;
  return graded(grade, unrestricted(type));
}

Type idr::view(Type type) {
  return graded({gradeOf(type).quantity, Permission::Plain}, unrestricted(type));
}

Type idr::atQuantity(Type type, Quantity quantity) {
  return graded({quantity, gradeOf(type).permission}, unrestricted(type));
}

bool idr::isExclusive(Type type) { return gradeOf(type).permission == Permission::Excl; }

Type idr::exclusive(Type type) {
  return graded({gradeOf(type).quantity, Permission::Excl}, unrestricted(type));
}

Quantity idr::times(Quantity a, Quantity b) {
  if (a == Quantity::One)
    return b;
  if (b == Quantity::One)
    return a;
  return Quantity::Many;
}

// A destination is written exactly once, so it is used exactly once.
Quantity idr::quantityOf(Type type) {
  return isa<DestType>(type) ? Quantity::One : gradeOf(type).quantity;
}

Value idr::throughLinear(Value value) {
  for (;;) {
    if (auto enter = value.getDefiningOp<LinEnterOp>()) {
      value = enter.getValue();
      continue;
    }
    auto use = value.getDefiningOp<LinUseOp>();
    auto enter = use ? use.getLinear().getDefiningOp<LinEnterOp>() : LinEnterOp();
    if (!enter)
      return value;
    value = enter.getValue();
  }
}

// A view or a share of an owned array is that array, and so is the array a
// linear position was entered with: what counting and linearity make of an
// array changes which value names it, not which cell it is.
Value idr::arrayRoot(Value array) {
  while (true) {
    Value next = throughLinear(array);
    if (auto borrow = next.getDefiningOp<BorrowOp>())
      next = borrow.getValue();
    else if (auto share = next.getDefiningOp<ShareOp>())
      next = share.getValue();
    if (next == array)
      return array;
    array = next;
  }
}

bool idr::fieldReadOnce(Value value, unsigned index) {
  unsigned reads = 0;
  SmallVector<Value, 4> work{value};
  while (!work.empty()) {
    Value held = work.pop_back_val();
    for (Operation *user : held.getUsers()) {
      if (isa<LinEnterOp, LinUseOp>(user)) {
        work.push_back(user->getResult(0));
        continue;
      }
      auto read = dyn_cast<FieldOp>(user);
      if (!read)
        return false;
      if (read.getIndex() == index)
        ++reads;
    }
  }
  return reads == 1;
}

// The operands of a closure or a suspension are its captures.
bool idr::holdsLinear(Value value) {
  Operation *made = value.getDefiningOp();
  return isa_and_nonnull<ClosureOp, SuspendOp>(made) &&
         llvm::any_of(made->getOperandTypes(),
                      [](Type type) { return quantityOf(type) == Quantity::One; });
}

// Not at all, or once: run by its one user, or entered into a linear type.
bool idr::takenOnce(Value value) {
  if (value.use_empty())
    return true;
  if (!value.hasOneUse())
    return false;
  Operation *user = *value.getUsers().begin();
  if (auto apply = dyn_cast<ApplyOp>(user))
    return apply.getCallee() == value;
  if (auto force = dyn_cast<ForceOp>(user))
    return force.getSuspension() == value;
  return isa<LinEnterOp>(user);
}

Type idr::fieldType(Type scrutinee, Type field) {
  if (isWorld(field))
    return field;
  return graded({times(quantityOf(scrutinee), quantityOf(field)), Permission::Plain},
                unrestricted(field));
}

Value idr::heldAs(OpBuilder &b, Location loc, Value value, Type type) {
  if (value.getType() == type)
    return value;
  if (quantityOf(type) == Quantity::One)
    return LinEnterOp::create(b, loc, type, value);
  return LinUseOp::create(b, loc, type, value);
}

namespace {

// An element of an array: a field type at no grade, and not the world,
// which has no runtime form to store.
bool isElementType(Type element) {
  return !isa<QType>(element) && !isWorld(element) && isFieldType(element);
}

// A value array: a ranked tensor without an encoding, of any rank and
// extents. After bufferization, its buffer: a memref in the default memory
// space, in the identity layout, of any rank and extents. Its element is
// no shaped value: an array of arrays is one array of a higher rank.
bool isValueArray(Type type) {
  auto shaped = dyn_cast<ShapedType>(type);
  if (!shaped || isa<ShapedType>(shaped.getElementType()) ||
      !isElementType(shaped.getElementType()))
    return false;
  if (auto tensor = dyn_cast<RankedTensorType>(type))
    return !tensor.getEncoding();
  auto memref = dyn_cast<MemRefType>(type);
  return memref && !memref.getMemorySpace() && memref.getLayout().isIdentity();
}

} // namespace

bool idr::isFieldType(Type type) {
  if (isWorld(type))
    return true;
  type = unrestricted(type);
  if (auto integer = dyn_cast<IntegerType>(type))
    return integer.isSignless() && llvm::is_contained({8u, 16u, 32u, 64u}, integer.getWidth());
  return isa<Float64Type, DataType, BoxType, FnType, LazyType, StrType, BigType, NatType>(type) ||
         isArray(type) || isValueArray(type);
}

// An array a world orders: at most one dimension, each dynamic, in the
// identity layout, in the world's memory, the shapes the runtime's array
// cell has (a length, then the elements in order), an IORef being the cell
// of one element, whose length is 1 and no value carries. The memory space
// tells it from a value buffer of the same element, which a cell may hold
// after it is shared and so cannot be written.
bool idr::isArray(Type type) {
  auto memref = dyn_cast<MemRefType>(type);
  if (!memref || memref.getRank() > 1 || !llvm::all_of(memref.getShape(), ShapedType::isDynamic) ||
      !memref.getLayout().isIdentity() || !isa_and_nonnull<WorldSpaceAttr>(memref.getMemorySpace()))
    return false;
  return isElementType(memref.getElementType());
}

bool idr::isRank1Array(Type type) {
  return isArray(type) && cast<MemRefType>(type).getRank() == 1;
}
