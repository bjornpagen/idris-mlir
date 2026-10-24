// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The literals of the scalar types of ours and the test a literal match
// makes of each, the integer a big's literal is as a key, how an Integer
// and a natural are read as numbers, and the names the printer gives a
// value of each.

#include "idr/IR/Control/KeyTests.h"
#include "idr/IR/Families/Families.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/OpImplementation.h"

#include <string>

using namespace mlir;
using namespace idr;

// A string's literal is a string attribute with no type: a typed one
// (`"x" : !idr.str`) is another attribute of the same text, which no
// literal of ours is, so one string has one literal.
bool StrType::isLiteral(Attribute literal) const {
  auto text = dyn_cast<StringAttr>(literal);
  return text && isa<NoneType>(text.getType());
}

ParseResult StrType::parseLiteral(AsmParser &parser, Attribute &literal) const {
  std::string bytes;
  if (parser.parseString(&bytes))
    return failure();
  literal = parser.getBuilder().getStringAttr(bytes);
  return success();
}

// A string is tested against a key by the op KeyTestOf names for it.
Value StrType::buildKeyTest(OpBuilder &builder, Location loc, Value held, Attribute key) const {
  return buildKeyTestOf<StrType>(builder, loc, held, key);
}

bool BigType::isLiteral(Attribute literal) const { return isa<BigAttr>(literal); }

ParseResult BigType::parseLiteral(AsmParser &parser, Attribute &literal) const {
  BigAttr big;
  if (parser.parseAttribute(big))
    return failure();
  literal = big;
  return success();
}

// A natural is never negative, which its type proves, and where its index
// term is a closed natural it is that natural: the one place a natural's
// literal is said. It is written as a big's; any other is no literal of it,
// which the op that holds it is refused for.
bool NatType::isLiteral(Attribute literal) const {
  auto big = dyn_cast<BigAttr>(literal);
  if (!big || big.getValue().isNegative())
    return false;
  families::Term index(getIndex());
  return index.kind() != TermKind::Natural ||
         (big.getValue().getActiveBits() <= 64 &&
          big.getValue().getZExtValue() == index.head().value);
}

ParseResult NatType::parseLiteral(AsmParser &parser, Attribute &literal) const {
  return BigType::get(getContext()).parseLiteral(parser, literal);
}

// An Integer and a natural are tested against a key by the op KeyTestOf
// names for each.
Value BigType::buildKeyTest(OpBuilder &builder, Location loc, Value held, Attribute key) const {
  return buildKeyTestOf<BigType>(builder, loc, held, key);
}
Value NatType::buildKeyTest(OpBuilder &builder, Location loc, Value held, Attribute key) const {
  return buildKeyTestOf<NatType>(builder, loc, held, key);
}

// A big's literal, as a key of a literal match or a constant, is its
// integer, held at its fewest signed bits.
APInt BigAttr::getKeyInteger() const { return getValue(); }

// An Integer is read as the integer it stands for, and a natural as one
// never negative besides; each is the big the big ops take.
NumericReading BigType::getNumericReading() const { return NumericReading::Integer; }
bool BigType::isCarriedAsBig() const { return true; }
NumericReading NatType::getNumericReading() const { return NumericReading::Natural; }
bool NatType::isCarriedAsBig() const { return true; }

void StrType::getAsmName(OpAsmSetNameFn setNameFn) const { setNameFn("s"); }
void BigType::getAsmName(OpAsmSetNameFn setNameFn) const { setNameFn("n"); }
void NatType::getAsmName(OpAsmSetNameFn setNameFn) const { setNameFn("n"); }
