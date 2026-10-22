// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The literals of the scalar types of ours, and the names the printer gives
// a value of each.

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

void StrType::getAsmName(OpAsmSetNameFn setNameFn) const { setNameFn("s"); }
void BigType::getAsmName(OpAsmSetNameFn setNameFn) const { setNameFn("n"); }
void NatType::getAsmName(OpAsmSetNameFn setNameFn) const { setNameFn("n"); }
