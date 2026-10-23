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

} // namespace idr

#endif // IDR_IR_INTERFACES_VOCABULARY_H
