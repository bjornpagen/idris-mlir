// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The words the dialect's question interfaces answer in: each question a
// reader once asked by testing an op, a type or an attribute against a
// list of classes is one method its subject answers, and these are the
// answers' types. The dialect's header includes this before the generated
// interfaces, so a method's signature names them; a type an answer names
// by reference is declared here and defined beside the code that builds
// it.
#ifndef IDR_IR_INTERFACES_VOCABULARY_H
#define IDR_IR_INTERFACES_VOCABULARY_H

#include "mlir/IR/Attributes.h"
#include "mlir/IR/Value.h"
#include "llvm/Support/Casting.h"

#include <cstdint>
#include <variant>

namespace idr {

// How an op uses a lifetime it takes: it only names it; it is a slot of its
// own function's frame there; it puts into it; or it passes it on to a
// callee, whose own use decides.
enum class LifetimeUse : std::uint8_t { Names, Slot, Puts, PassesOn };

// The lifetimes open where an op stands, which an op's own lifetime rule
// reads; the lifetimes' verifier defines it.
class OpenLifetimes;

// How a value of a type is read as a number: as an Integer, as a natural,
// or as a word's bits.
enum class NumericReading : std::uint8_t { Integer, Natural, Bits };

// How a constant value is laid out as static data: a closed sum, defined
// after the attributes its alternatives hold (Interfaces/StaticForm.h).
struct StaticForm;

// An attribute of a class the dialect generates after this header, held
// as itself: the handle is complete before its class is, so a closed sum
// an attribute interface returns by value, whose interface is generated
// before the attributes, may hold one, and its reader takes the attribute
// at its class by `get`. A handle is made only of an attribute of its
// class, which `get` asserts.
template <class A>
struct AttrOf {
  mlir::Attribute held;
  A get() const { return llvm::cast<A>(held); }
};

class ClosureAttr;
class ConAttr;

// A constant that holds no closure: a big, or an attribute that is no
// constant of ours (a string, an integer, a Double).
struct HoldsNoClosure {};

// How a constant holds closures, the answer of
// ConstantAttrInterface::getClosureHolding: it is a closure, which holds
// itself; a constructor, which holds those its fields hold; or it holds
// none. A reader that walks a constant's closures folds it with `match`, so
// a constant of ours that gains a way to hold one is refused at every
// reader that forgot it.
struct ClosureHolding : std::variant<AttrOf<ClosureAttr>, AttrOf<ConAttr>, HoldsNoClosure> {
  using variant::variant;
};

// How `value` holds closures: a constant of ours answers through
// ConstantAttrInterface, and any other attribute holds none.
ClosureHolding closureHoldingOf(mlir::Attribute value);

// What a match's region knows of its scrutinee: the value it binds it as,
// whose type says what it knows (a data match's case or default, refined; a
// literal match's default, at the scrutinee's own type), or the literal the
// scrutinee equals where the region binds nothing (a literal match's case).
namespace case_scrutinee {
struct Bound {
  mlir::BlockArgument value;
};
struct Equals {
  mlir::Attribute literal;
};
} // namespace case_scrutinee
struct CaseScrutinee : std::variant<case_scrutinee::Bound, case_scrutinee::Equals> {
  using variant::variant;
};

namespace families {
// A pattern type's match against an instance in progress: it compares index
// terms and queues the parts a match pairs (Families/Matching.h).
class PatternMatch;
// What an op's scope rule reads of the scope walk where it stands
// (Families/Scope.h).
class ScopeQuery;
} // namespace families

// The cursor whose base the lifetime an op binds extends, read from the
// op's own class, which names it `base`.
template <class Op>
mlir::Value cursorBaseOfOp(Op op) {
  return op.getBase();
}

// The lifetime a derived lifetime is derived from, read from the op's own
// class, which names it `lifetime`.
template <class Op>
mlir::Value derivedFromOfOp(Op op) {
  return op.getLifetime();
}

// The constants an opener's class holds of itself, which the generated code
// specializes for each opener after the ops (Lifetimes.h).
template <class Op>
struct LifetimeOpener;

// What the package of a per-level opener's lifetime holds: the constant of
// its class, which only an opener that may be per level holds (`packed`).
// Its type is the dialect's enum, which this header comes before.
template <class Op>
auto packedOfOp(Op) {
  return LifetimeOpener<Op>::packed;
}

} // namespace idr

#endif // IDR_IR_INTERFACES_VOCABULARY_H
