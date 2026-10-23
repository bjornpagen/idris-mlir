// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a value of each type holds, asked through ValueFactsTypeInterface:
// every type of the dialect answers from the facts its specification
// declares, printed into its class, so no answer is written here; the
// builtin types a value may have answer as external models, attached when
// the dialect registers its types, with the literals of the builtin integers
// and of f64 and the test a literal match makes of each. The free functions
// are the one way a reader asks (Grades.h).

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"

#include "mlir/Dialect/Arith/IR/Arith.h"

using namespace mlir;
using namespace idr;

namespace {

// What a builtin scalar or vector holds: no reference, and it is used as
// often as its grade says. A vector's elements are scalars.
template <typename T>
struct ScalarFacts : ValueFactsTypeInterface::ExternalModel<ScalarFacts<T>, T> {
  bool holdsReferences(Type) const { return false; }
  ByType getByType(Type) const { return ByType::UsedAsGraded; }
  bool isCounted(Type) const { return false; }
  bool isCellPointer(Type) const { return false; }
};

// An array's cell is a reference, used as often as its grade says. A
// buffer is counted; a value array is counted as its buffer, after
// bufferization. Its value is a descriptor, the cell with what of its shape
// the type leaves open, not one pointer.
template <typename T, bool counted>
struct ArrayFacts : ValueFactsTypeInterface::ExternalModel<ArrayFacts<T, counted>, T> {
  bool holdsReferences(Type) const { return true; }
  ByType getByType(Type) const { return ByType::UsedAsGraded; }
  bool isCounted(Type) const { return counted; }
  bool isCellPointer(Type) const { return false; }
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

// A literal of f64 is a Double a literal match compares by IEEE's equality,
// so one key is one value it matches: never a NaN, which equals nothing,
// nor negative zero, which equals positive zero and is written as it.
struct DoubleLiterals : LiteralTypeInterface::ExternalModel<DoubleLiterals, Float64Type> {
  bool isLiteral(Type type, Attribute literal) const {
    auto real = dyn_cast<FloatAttr>(literal);
    return real && real.getType() == type && !real.getValue().isNaN() &&
           !real.getValue().isNegZero();
  }

  ParseResult parseLiteral(Type type, AsmParser &parser, Attribute &literal) const {
    APFloat value(APFloat::IEEEdouble());
    SMLoc loc = parser.getCurrentLocation();
    if (parser.parseFloat(APFloat::IEEEdouble(), value))
      return failure();
    if (value.isNaN() || value.isNegZero())
      return parser.emitError(loc, "key is no literal of ")
             << type << ": a NaN equals no Double, and negative zero is written as zero";
    literal = FloatAttr::get(type, value);
    return success();
  }

  // Equal as the runtime's match compares a Double with its key, by IEEE's
  // ordered equality: either zero is the other, and a NaN equals nothing.
  bool sameLiteral(Type, Attribute a, Attribute b) const {
    return cast<FloatAttr>(a).getValue().compare(cast<FloatAttr>(b).getValue()) ==
           APFloat::cmpEqual;
  }

  // The same equality at run time: arith's ordered comparison of the plain
  // Double and the key's constant, under which no key is a NaN.
  Value buildKeyTest(Type, OpBuilder &builder, Location loc, Value held, Attribute key) const {
    Value literal = arith::ConstantOp::create(builder, loc, cast<TypedAttr>(key));
    return arith::CmpFOp::create(builder, loc, arith::CmpFPredicate::OEQ, held, literal);
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
  Float64Type::attachInterface<DoubleLiterals>(context);
  Float80Type::attachInterface<ScalarFacts<Float80Type>>(context);
  Float128Type::attachInterface<ScalarFacts<Float128Type>>(context);
  VectorType::attachInterface<ScalarFacts<VectorType>>(context);
  MemRefType::attachInterface<ArrayFacts<MemRefType, true>>(context);
  UnrankedMemRefType::attachInterface<ArrayFacts<UnrankedMemRefType, true>>(context);
  RankedTensorType::attachInterface<ArrayFacts<RankedTensorType, false>>(context);
  UnrankedTensorType::attachInterface<ArrayFacts<UnrankedTensorType, false>>(context);
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
