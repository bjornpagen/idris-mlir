// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The words the dialect's question interfaces answer in: each question a
// reader once asked by testing an op, a type or an attribute against a
// list of classes is one method its subject answers, and these are the
// answers' types. The dialect's header includes this before the generated
// interfaces, so a method's signature names them; a type an answer names
// by reference is declared here and defined beside the code that builds
// it. mlir-tblgen defines each interface's model out of line, before the
// attributes and types are, so every answer returned by value is complete
// here, and holds what the dialect generates later by a handle.
#ifndef IDR_IR_INTERFACES_VOCABULARY_H
#define IDR_IR_INTERFACES_VOCABULARY_H

#include "idr/IR/Grades.h"

#include "mlir/IR/Attributes.h"
#include "mlir/IR/BuiltinAttributeInterfaces.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinTypeInterfaces.h"
#include "mlir/IR/Types.h"
#include "mlir/IR/Value.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/Support/Casting.h"

#include <cstdint>
#include <optional>
#include <variant>

// The kind of word a runtime component is (layout::Word), which a value's
// run-time words name.
#include "idr/IR/Generated/Words.h.inc"

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

// A type of a class the dialect generates after this header, held as
// itself, as AttrOf holds an attribute: made only of a type of its class,
// which `get` asserts.
template <class T>
struct TypeOf {
  mlir::Type held;
  T get() const { return llvm::cast<T>(held); }
};

class BigAttr;
class ClosureAttr;
class ConAttr;
class DataType;
class FnType;
class LazyType;

//===----------------------------------------------------------------------===//
// What a value of a type is at run time
//===----------------------------------------------------------------------===//

// The answer of ValueFactsTypeInterface::getRunTimeWords, each type's own:
// one pointer, of a kind of word (a cell's address, a cell before its
// init); one integer `bits` wide, a big's word; a builtin scalar or vector,
// its own word, of which no count is kept; no word, a lifetime whose kind
// is erased at run time; one address no count is kept of per component of
// a value of `of`, each that component's slot in the place it is written
// (a destination); an array's cell and what of its descriptor its type
// leaves to the value; or a data type's words, the ones it computed when it
// was made. Every count of a value's components folds this, so a way of
// being at run time a type gains is refused at every reader that forgot it.
namespace run_time_words {
struct Pointer {
  layout::Word word;
};
struct Integer {
  unsigned bits;
  layout::Word word;
};
struct Itself {
  mlir::Type type;
};
struct NoWord {};
struct Addresses {
  mlir::Type of;
};
struct Descriptor {
  mlir::ShapedType array;
};
struct Held {
  TypeOf<DataType> data;
};
} // namespace run_time_words

struct RunTimeWords
    : std::variant<run_time_words::Pointer, run_time_words::Integer, run_time_words::Itself,
                   run_time_words::NoWord, run_time_words::Addresses, run_time_words::Descriptor,
                   run_time_words::Held> {
  using variant::variant;
};

// The words of a value of `type`, held at `hold` where a grade around it
// says so, as its type answers (ValueFactsTypeInterface). A type no model
// answers for is of another dialect, which only the lowering makes: no
// value of the program, it is its own word.
RunTimeWords runTimeWordsOf(mlir::Type type, std::optional<Hold> hold = std::nullopt);

//===----------------------------------------------------------------------===//
// What a value of a type carries where it moves
//===----------------------------------------------------------------------===//

// The carrier of labels a value is, a closure or a suspension, each by its
// type: a closure's label is called with the closure's inputs besides its
// captures, its arity; a suspension's with none, every parameter of a
// suspended function being a capture. Either is a cell, a counted
// reference too.
namespace carrying {
struct Closure {
  TypeOf<FnType> type;
  unsigned arity() const;
};
struct Suspension {
  TypeOf<LazyType> type;
  unsigned arity() const { return 0; }
};
} // namespace carrying

struct LabelCarrier : std::variant<carrying::Closure, carrying::Suspension> {
  using variant::variant;
};

// A counted reference and no label; or nothing a reader of moves follows.
namespace carrying {
struct Reference {};
struct Nothing {};
} // namespace carrying

// What a value of a type carries where it moves, for the label solve and
// for counting's flow, the answer of ValueFactsTypeInterface::getCarrying:
// a closure's or a suspension's labels, a counted reference alone, or
// nothing. Each alternative is a state a value is in, so no answer holds a
// label without its cell's reference, or two labels at once.
struct Carrying : std::variant<LabelCarrier, carrying::Reference, carrying::Nothing> {
  using variant::variant;
};

// What a value of `type` carries, at any grade, as its type answers. A type
// no model answers for is of another dialect, and carries nothing.
Carrying carryingOf(mlir::Type type);

// Whether a value of `type`, at any grade, is a cell's memory, a cell
// before its init or a reuse token, as its type answers: what counting
// builds into and what a test of sharing gives for what it took apart.
bool isCellMemory(mlir::Type type);

//===----------------------------------------------------------------------===//
// How a constant is laid out as static data
//===----------------------------------------------------------------------===//

// The answer of ConstantAttrInterface::getStaticForm for an attribute of
// ours, and of staticFormOf for any constant: a string, its attribute, at
// the string's own datum; an Integer or a natural, at a big's datum or in
// its word; a numeral, its value at its place, a word of its layout's width or
// a natural where its place is laid out as one; an integer or a Double,
// its own type's literal; poison, which stands for a cell pointer only; a
// constructor of a family laid out in place, its fields in its words; or a
// constructor in a cell of its own. A closure reaches static data only as
// its label's constructor, defunctionalization having rewritten it. Each
// writer of static data folds it with `match`, so a form it gains is
// refused at every writer that forgot it.
namespace static_form {
struct Text {
  mlir::StringAttr value;
};
struct Big {
  AttrOf<BigAttr> value;
};
struct Numeral {
  TypeOf<DataType> place;
  std::uint64_t value;
};
struct Word {
  mlir::TypedAttr literal;
};
struct Nothing {};
struct InPlace {
  AttrOf<ConAttr> con;
};
struct Cell {
  AttrOf<ConAttr> con;
};
} // namespace static_form

struct StaticForm
    : std::variant<static_form::Text, static_form::Big, static_form::Numeral, static_form::Word,
                   static_form::Nothing, static_form::InPlace, static_form::Cell> {
  using variant::variant;
};

// How `value`, held at `held`, is laid out as static data: an attribute of
// ours answers through ConstantAttrInterface, and the upstream attributes a
// constant holds are classified where it is defined, the one place they are
// named.
StaticForm staticFormOf(mlir::Attribute value, mlir::Type held);

//===----------------------------------------------------------------------===//
// How a constant holds closures
//===----------------------------------------------------------------------===//

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
// scrutinee equals, which its type cannot say (a literal match's case,
// whose binding is that literal).
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
