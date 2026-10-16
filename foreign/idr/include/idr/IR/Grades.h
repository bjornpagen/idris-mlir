// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The grades: what Idris proved of a value, kept in its type where no pass
// can drop it, and the questions every pass asks of a graded type or value.
// They are declared over mlir::Type and mlir::Value, before the dialect's
// generated types: the generated type builders and constraints name them.
#ifndef IDR_IR_GRADES_H
#define IDR_IR_GRADES_H

#include "mlir/IR/Builders.h"
#include "mlir/IR/Types.h"
#include "mlir/IR/Value.h"
#include "llvm/ADT/Hashing.h"
#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <concepts>
#include <iterator>
#include <optional>

// A grade is a pair of two of the enums (IdrBase.td). The generated file has
// no guard of its own, so this header is where the dialect includes it.
#include "idr/IR/IdrEnums.h.inc"

namespace idr {

// A grade: the quantity is the number of uses Idris allows, one or many
// (Quantity); the permission is what the value owns, plain (nothing to
// say), a borrow, one reference of its own, or an exclusive cell graph,
// which the owned stage decides. A plain type T is the grade (many, plain).
struct Grade {
  Quantity quantity = Quantity::Many;
  Permission permission = Permission::Plain;
  bool operator==(const Grade &) const = default;
  bool plain() const { return quantity == Quantity::Many && permission == Permission::Plain; }
};

inline llvm::hash_code hash_value(Grade grade) {
  return llvm::hash_combine(static_cast<unsigned>(grade.quantity),
                            static_cast<unsigned>(grade.permission));
}

// The grade of a type: its own for !idr.q, (many, plain) for a plain type.
Grade gradeOf(mlir::Type type);

// The type `value` at `grade`, in canonical form: `value` itself at
// (many, plain), and never a grade of a graded type.
mlir::Type graded(Grade grade, mlir::Type value);

// The spellings: !idr.lin<T> and !idr.world.
mlir::Type linear(mlir::Type value);
mlir::Type world(mlir::MLIRContext *ctx);

// Whether a type is a linear value other than the world (one that entered
// its grade and is used out of it), which its grade says; or the world,
// which its carrier says, graded or stripped.
bool isLinear(mlir::Type type);
bool isWorld(mlir::Type type);

// The owned stage's grades: a value that holds a reference of its own
// (own, or excl), and the view of it, which holds none: a borrow for a type
// of ours, plain for a builtin buffer, which upstream's ops take ungraded.
// `owned` and `view` keep the quantity and change the permission;
// `atQuantity` keeps the permission and changes the quantity.
// `atPermission` keeps the quantity, which is Idris's, and sets the
// permission: how a value is compared with a slot declared at another
// permission (a plain field, element or yield, a dup's owned result, a
// store's plain carrier), whatever counting made of it.
bool isOwned(mlir::Type type);
mlir::Type owned(mlir::Type type);
mlir::Type view(mlir::Type type);
mlir::Type atQuantity(mlir::Type type, Quantity quantity);
mlir::Type atPermission(mlir::Type type, Permission permission);

// Whether a value holds the only reference to every cell of its cell
// graph (the excl permission), which idr-rc proves and writes into the
// type: taking it apart needs no count test, and its cells no null test.
// `exclusive` is the type with that permission, at its own quantity.
bool isExclusive(mlir::Type type);
mlir::Type exclusive(mlir::Type type);

// Idris's product of quantities: one is the unit, and many times many is
// many.
Quantity times(Quantity a, Quantity b);

// How often a value may be used, as its type says: exactly once
// (!idr.lin<T> and the world), or any number of times.
Quantity quantityOf(mlir::Type type);

// The type of the value itself: T for !idr.lin<T>, the type otherwise.
mlir::Type unrestricted(mlir::Type type);

// Whether a slot of `type` holds a closure, or a suspension, at any
// quantity: the value's carrier says, whatever linearity a rewrite keeps.
bool isClosureType(mlir::Type type);
bool isLazyType(mlir::Type type);

// The values from `start` along `step` until it gives nothing, `start`
// first, each passed once. A step goes to an operand of the op that
// defines a value, which dominates it in a reachable block; in an
// unreachable one an op may use its own result, so a chain may close on
// itself, and it ends where it would come back. Every walk up a chain of
// definitions is one of these.
llvm::SmallVector<mlir::Value, 4>
definitionChain(mlir::Value start, llvm::function_ref<std::optional<mlir::Value>(mlir::Value)> step);

// The value `value` was made from, seen through the linear positions it
// passed: `lin.enter %x` and `lin.use (lin.enter %x)` are %x. What a value
// is (its constructor, a field) does not change on the way; whether a read
// may take a linear part of it is the reader's to decide.
mlir::Value throughLinear(mlir::Value value);

// The array an access reads or writes: a view or a share of an owned array
// is that array, and so is the array a linear position was entered with.
mlir::Value arrayRoot(mlir::Value array);

// Whether two accesses name the same element: the same array, seen through
// arrayRoot, at the same indices, each seen through the in-bounds guard
// that checked it, or constants of the same value.
bool sameElement(mlir::Value array, mlir::ValueRange indices, mlir::Value otherArray,
                 mlir::ValueRange otherIndices);

// Whether the field at `index` of a constructor value is read exactly once,
// and the value is read no other way: through its grade changes every use
// is a field read, and one of them reads `index`. Then a linear operand at
// that index moves into its one read.
bool fieldReadOnce(mlir::Value value, unsigned index);

// A closure or a suspension that captures a linear value is used once, as
// what it holds is: by the op that runs it where it is made (an apply of
// the closure, a force of the suspension), or by entering a linear type,
// whose one use the linearity check then follows. Any other use could run
// it twice and use the capture twice. Whether `value` is such a closure or
// suspension, and whether the uses of `value` are none or such a one. A
// rewrite that would give one the uses of another value asks it of that
// value.
bool holdsLinear(mlir::Value value);
bool takenOnce(mlir::Value value);

// The type at which a region of a match binds a field of its scrutinee:
// the field's value at the product of the scrutinee's quantity and the
// field's, as Idris binds a pattern variable (a linear field of a value
// used many times is used many times; a field of a linear value is used as
// the field says). Once counting has graded the scrutinee, the field is a
// view of it, as view() gives one. The world, which is only ever at its own
// grade, stays the world.
mlir::Type fieldType(mlir::Type scrutinee, mlir::Type field);

// `value` held as `type`, its own type at another quantity: entered into a
// linear type, or used out of one; itself when the types agree.
mlir::Value heldAs(mlir::OpBuilder &b, mlir::Location loc, mlir::Value value, mlir::Type type);

// An application compares a closure's declared types with the values it is
// given. Reference counting grades what a value owns after the closure type
// is fixed; the quantity Idris proved stays, and the carrier is the value.
template <typename Types>
concept TypeSequence = requires(Types types) {
  { *std::begin(types) } -> std::convertible_to<mlir::Type>;
  std::end(types);
};
template <TypeSequence Expected, TypeSequence Actual>
bool sameCarriers(Expected &&expected, Actual &&actual) {
  return llvm::equal(expected, actual, [](mlir::Type a, mlir::Type b) {
    return gradeOf(a).quantity == gradeOf(b).quantity && unrestricted(a) == unrestricted(b);
  });
}

// What a value of `type` holds, as the type's ValueFactsTypeInterface
// answers (IdrInterfaces.td): every type of the dialect and every builtin
// type a value may have answers it. A type of another dialect, which only
// the lowering makes, is no value of the program and holds none of these.
bool holdsReferences(mlir::Type type);
bool holdsWorld(mlir::Type type);
bool holdsClosure(mlir::Type type);
bool isCounted(mlir::Type type);
bool isCellPointer(mlir::Type type);

// The types a field of a constructor may have: the world, a word, a
// runtime type of ours, an array a world orders, and a value array, a
// ranked tensor or, after bufferization, its buffer.
bool isFieldType(mlir::Type type);

// An array a world orders: `memref<?xE, #idr.world>`, or `memref<E,
// #idr.world>` (an IORef), of a field type E at no grade (Idr_ArrayType).
bool isArray(mlir::Type type);

// An array a world orders of one dimension, `memref<?xE, #idr.world>`: one
// that has a length.
bool isRank1Array(mlir::Type type);

} // namespace idr

#endif // IDR_IR_GRADES_H
