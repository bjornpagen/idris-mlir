// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The grades: a type at a grade, its spellings, what its grade says of how
// a value may be used and what it owns, and the values seen through the
// positions their grades put them in. Whether two accesses name one element
// is the arrays' unit's.

#include "idr/IR/IdrDialect.h"
#include "idr/Support/Worklist.h"

#include "llvm/ADT/SmallPtrSet.h"

#include "llvm/Support/ErrorHandling.h"

#include <optional>

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

namespace {

// Whether a value at `permission` holds a reference of its own.
bool holdsOwn(Permission permission) {
  switch (permission) {
  case Permission::Plain:
  case Permission::Borrow:
    return false;
  case Permission::Own:
  case Permission::Excl:
    return true;
  }
  llvm_unreachable("a permission");
}

} // namespace

bool idr::isOwned(Type type) { return holdsOwn(gradeOf(type).permission); }

// A value that holds no reference of its own, plain or a borrow, comes to
// hold one; own and excl stay.
Type idr::owned(Type type) {
  Grade grade = gradeOf(type);
  if (!holdsOwn(grade.permission))
    grade.permission = Permission::Own;
  return graded(grade, unrestricted(type));
}

// At the owned stage a value of ours that holds no reference of its own is
// a borrow, the grade that says so, never plain. A builtin buffer stays
// plain: upstream's memref ops take no graded operand, and the world has
// only its own grade.
Type idr::view(Type type) {
  Type value = unrestricted(type);
  bool ours = isa<IdrDialect>(value.getDialect()) && !isWorld(value);
  return graded({gradeOf(type).quantity, ours ? Permission::Borrow : Permission::Plain}, value);
}

Type idr::atQuantity(Type type, Quantity quantity) {
  return graded({quantity, gradeOf(type).permission}, unrestricted(type));
}

Type idr::atPermission(Type type, Permission permission) {
  return graded({gradeOf(type).quantity, permission}, unrestricted(type));
}

bool idr::isExclusive(Type type) { return gradeOf(type).permission == Permission::Excl; }

Type idr::exclusive(Type type) {
  return graded({gradeOf(type).quantity, Permission::Excl}, unrestricted(type));
}

Quantity idr::times(Quantity a, Quantity b) {
  switch (a) {
  case Quantity::One:
    return b;
  case Quantity::Many:
    return Quantity::Many;
  }
  llvm_unreachable("a quantity");
}

// A destination is written exactly once, so it is used exactly once.
Quantity idr::quantityOf(Type type) {
  return isa<DestType>(type) ? Quantity::One : gradeOf(type).quantity;
}

namespace {

// What `value` was entered into its linear position from, when it is one:
// `lin.enter %x`, or `lin.use (lin.enter %x)`.
std::optional<Value> enteredFrom(Value value) {
  if (auto enter = value.getDefiningOp<LinEnterOp>())
    return enter.getValue();
  if (auto use = value.getDefiningOp<LinUseOp>())
    if (auto enter = use.getLinear().getDefiningOp<LinEnterOp>())
      return enter.getValue();
  return std::nullopt;
}

} // namespace

SmallVector<Value, 4> idr::definitionChain(Value start,
                                           function_ref<std::optional<Value>(Value)> step) {
  SmallVector<Value, 4> chain{start};
  llvm::SmallPtrSet<Value, 4> passed{start};
  for (std::optional<Value> next = step(start); next && passed.insert(*next).second;
       next = step(*next))
    chain.push_back(*next);
  return chain;
}

Value idr::throughLinear(Value value) { return definitionChain(value, enteredFrom).back(); }

// A view or a share of an owned array is that array, and so is the array a
// linear position was entered with: what counting and linearity make of an
// array changes which value names it, not which cell it is. Every op that
// only changes a grade says so (ResultCarriesOperand).
Value idr::arrayRoot(Value array) {
  return definitionChain(array, [](Value value) -> std::optional<Value> {
           Operation *grade = value.getDefiningOp();
           if (grade && grade->hasTrait<ResultCarriesOperand>())
             return grade->getOperand(0);
           return std::nullopt;
         }).back();
}

// Each value the grade changes make of `value` is looked at once, and each
// is the result of a use of the one before, so the walk ends with them.
bool idr::fieldReadOnce(Value value, unsigned index) {
  unsigned reads = 0;
  OnceWorklist<Value> work;
  work.push(value);
  while (std::optional<Value> held = work.pop()) {
    for (Operation *user : held->getUsers()) {
      if (user->hasTrait<ResultCarriesOperand>()) {
        work.push(user->getResult(0));
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

// Not at all, or once: run by its one user, or given a grade of quantity
// one, which only changes its grade.
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
  return user->hasTrait<ResultCarriesOperand>() &&
         quantityOf(user->getResult(0).getType()) == Quantity::One;
}

Type idr::fieldType(Type scrutinee, Type field) {
  if (isWorld(field))
    return field;
  Type plain = graded({times(quantityOf(scrutinee), quantityOf(field)), Permission::Plain},
                      unrestricted(field));
  // Before counting no value is graded; after it, a field read out of a
  // value is a view of that value.
  return gradeOf(scrutinee).permission == Permission::Plain ? plain : view(plain);
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

// A runtime value of ours is an element type of memref, which its ODS says
// beside it, and so a field's type; the dialect's other types (a grade, the
// world's carrier, a token, a destination) are no values a cell holds.
bool idr::isFieldType(Type type) {
  if (isWorld(type))
    return true;
  type = unrestricted(type);
  if (auto integer = dyn_cast<IntegerType>(type))
    return integer.isSignless() && llvm::is_contained({8u, 16u, 32u, 64u}, integer.getWidth());
  if (isa<IdrDialect>(type.getDialect()))
    return isa<MemRefElementTypeInterface>(type);
  return isa<Float64Type>(type) || isArray(type) || isValueArray(type);
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
