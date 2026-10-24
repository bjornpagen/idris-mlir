// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a value of each type holds, asked through ValueFactsTypeInterface:
// every type of the dialect answers from the facts its specification
// declares, printed into its class where they are the same for every value
// of it; an answer its parameters decide is written here (a lifetime's
// words, a reuse token's, a destination's, a cell's carrying), beside the
// type's whose answers are all computed (a grade's, Grades.cpp; a data
// type's, Types.cpp). The builtin types a value may have answer as external
// models, attached when the dialect registers its types, with the literals
// of the builtin integers and the test a literal match makes of one. The
// free functions are the one way a reader asks (Grades.h,
// Interfaces/Vocabulary.h).

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Lifetimes.h"

#include "mlir/Dialect/Arith/IR/Arith.h"

#include <concepts>

using namespace mlir;
using namespace idr;

namespace {

// What a builtin scalar or vector holds: no reference, and it is used as
// often as its grade says. A vector's elements are scalars. It is its own
// word at run time, and it carries nothing a reader of moves follows.
template <typename T>
struct ScalarFacts : ValueFactsTypeInterface::ExternalModel<ScalarFacts<T>, T> {
  bool holdsReferences(Type) const { return false; }
  ByType getByType(Type) const { return ByType::UsedAsGraded; }
  bool isCounted(Type) const { return false; }
  bool isCellPointer(Type) const { return false; }
  RunTimeWords getRunTimeWords(Type type, std::optional<Hold>) const {
    return run_time_words::Itself{type};
  }
  Carrying getCarrying(Type) const { return carrying::Nothing{}; }
  bool isCellMemory(Type) const { return false; }
};

// What an array is at run time: a ranked one, its cell and what of its
// descriptor its type leaves to the value; an unranked one, whose shape no
// type states, its cell's address.
run_time_words::Descriptor arrayWords(MemRefType array) { return {array}; }
run_time_words::Descriptor arrayWords(RankedTensorType array) { return {array}; }
run_time_words::Pointer arrayWords(UnrankedMemRefType) { return {layout::Word::Cell}; }
run_time_words::Pointer arrayWords(UnrankedTensorType) { return {layout::Word::Cell}; }

// An array's cell is a reference, used as often as its grade says. A
// buffer, one of upstream's memrefs, is counted; a value array, one of its
// tensors, is counted as its buffer, after bufferization, and not as
// itself. Which of the two an array is, upstream's class hierarchy says.
// Its value is a descriptor, the cell with what of its shape the type
// leaves open, not one pointer. It carries its cell's reference.
template <typename T>
  requires std::derived_from<T, BaseMemRefType> || std::derived_from<T, TensorType>
struct ArrayFacts : ValueFactsTypeInterface::ExternalModel<ArrayFacts<T>, T> {
  bool holdsReferences(Type) const { return true; }
  ByType getByType(Type) const { return ByType::UsedAsGraded; }
  bool isCounted(Type) const { return std::derived_from<T, BaseMemRefType>; }
  bool isCellPointer(Type) const { return false; }
  RunTimeWords getRunTimeWords(Type type, std::optional<Hold>) const {
    return arrayWords(cast<T>(type));
  }
  Carrying getCarrying(Type) const { return carrying::Reference{}; }
  bool isCellMemory(Type) const { return false; }
};

// A literal of an integer type is an integer of that type, written as a
// number that fits its width; i1's are written true and false too.
struct IntegerLiterals : LiteralTypeInterface::ExternalModel<IntegerLiterals, IntegerType> {
  bool isLiteral(Type type, Attribute literal) const {
    auto integer = dyn_cast<IntegerAttr>(literal);
    return integer && integer.getType() == type;
  }

  ParseResult parseLiteral(Type type, AsmParser &parser, Attribute &literal) const {
    auto integer = cast<IntegerType>(type);
    unsigned width = integer.getWidth();
    if (width == 1) {
      if (succeeded(parser.parseOptionalKeyword("true"))) {
        literal = IntegerAttr::get(integer, 1);
        return success();
      }
      if (succeeded(parser.parseOptionalKeyword("false"))) {
        literal = IntegerAttr::get(integer, 0);
        return success();
      }
    }
    APInt value;
    SMLoc loc = parser.getCurrentLocation();
    if (parser.parseInteger(value))
      return failure();
    if ((value.isNegative() ? value.getSignificantBits() : value.getActiveBits()) > width)
      return parser.emitError(loc, "key does not fit in ") << type;
    literal = IntegerAttr::get(
        integer, value.isNegative() ? value.sextOrTrunc(width) : value.zextOrTrunc(width));
    return success();
  }

  // A word is its key where the two are one integer: arith's equality of
  // the plain word and the key's constant.
  Value buildKeyTest(Type, OpBuilder &builder, Location loc, Value held, Attribute key) const {
    Value literal = arith::ConstantOp::create(builder, loc, cast<TypedAttr>(key));
    return arith::CmpIOp::create(builder, loc, arith::CmpIPredicate::eq, held, literal);
  }
};

} // namespace

void IdrDialect::registerValueFacts() {
  MLIRContext &context = *getContext();
  IntegerType::attachInterface<ScalarFacts<IntegerType>>(context);
  IntegerType::attachInterface<IntegerLiterals>(context);
  IndexType::attachInterface<ScalarFacts<IndexType>>(context);
  BFloat16Type::attachInterface<ScalarFacts<BFloat16Type>>(context);
  Float16Type::attachInterface<ScalarFacts<Float16Type>>(context);
  Float32Type::attachInterface<ScalarFacts<Float32Type>>(context);
  Float64Type::attachInterface<ScalarFacts<Float64Type>>(context);
  Float80Type::attachInterface<ScalarFacts<Float80Type>>(context);
  Float128Type::attachInterface<ScalarFacts<Float128Type>>(context);
  VectorType::attachInterface<ScalarFacts<VectorType>>(context);
  MemRefType::attachInterface<ArrayFacts<MemRefType>>(context);
  UnrankedMemRefType::attachInterface<ArrayFacts<UnrankedMemRefType>>(context);
  RankedTensorType::attachInterface<ArrayFacts<RankedTensorType>>(context);
  UnrankedTensorType::attachInterface<ArrayFacts<UnrankedTensorType>>(context);
}

// A type no model answers for is of another dialect, which only the
// lowering makes: no value of the program, it holds none of these.
bool idr::holdsReferences(Type type) {
  auto facts = dyn_cast<ValueFactsTypeInterface>(type);
  return facts && facts.holdsReferences();
}

// Nor does its type fix how a value of it is used: it is used as its
// grade says.
ByType idr::byTypeOf(Type type) {
  auto facts = dyn_cast<ValueFactsTypeInterface>(type);
  return facts ? facts.getByType() : ByType::UsedAsGraded;
}

bool idr::isLinearByType(Type type) { return byTypeOf(type) == ByType::UsedOnceByType; }

bool idr::isCounted(Type type) {
  auto facts = dyn_cast<ValueFactsTypeInterface>(type);
  return facts && facts.isCounted();
}

bool idr::isCellPointer(Type type) {
  auto facts = dyn_cast<ValueFactsTypeInterface>(type);
  return facts && facts.isCellPointer();
}

// A type no model answers for is of another dialect, which only the
// lowering makes: its own word, carrying nothing, no cell's memory.
RunTimeWords idr::runTimeWordsOf(Type type, std::optional<Hold> hold) {
  auto facts = dyn_cast<ValueFactsTypeInterface>(type);
  return facts ? facts.getRunTimeWords(hold) : RunTimeWords(run_time_words::Itself{type});
}

Carrying idr::carryingOf(Type type) {
  auto facts = dyn_cast<ValueFactsTypeInterface>(type);
  return facts ? facts.getCarrying() : Carrying(carrying::Nothing{});
}

bool idr::isCellMemory(Type type) {
  auto facts = dyn_cast<ValueFactsTypeInterface>(type);
  return facts && facts.isCellMemory();
}

// A closure's label is called with the closure's inputs besides its
// captures.
unsigned carrying::Closure::arity() const {
  return static_cast<unsigned>(type.get().getInputs().size());
}

//===----------------------------------------------------------------------===//
// The answers a type's parameters decide
//===----------------------------------------------------------------------===//

// A lifetime is what its kind lowers to: nothing, for a lifetime nothing
// allocates into, else a pointer no count is kept of.
RunTimeWords LifetimeType::getRunTimeWords(std::optional<Hold>) const {
  if (getKind().lowered() == Lowered::NoValue)
    return run_time_words::NoWord{};
  return run_time_words::Pointer{layout::Word::Uncounted};
}

// A reuse token is its cell's address, which is never null where its grade
// says it holds its cell, and is null where its take found the cell shared.
RunTimeWords ReuseTokenType::getRunTimeWords(std::optional<Hold> hold) const {
  return run_time_words::Pointer{hold && hold->claims(Unique::Deep) ? layout::Word::Cell
                                                                    : layout::Word::MaybeCell};
}

// A destination is an address per component of what it takes, each that
// component's slot in the place it is written.
RunTimeWords DestType::getRunTimeWords(std::optional<Hold>) const {
  return run_time_words::Addresses{getValue()};
}

// A cell carries what the box its init makes of it carries: it is that box
// before it is one, so whether a box is new to anyone is whether its cell
// was.
Carrying CellType::getCarrying() const { return carryingOf(getValue()); }
