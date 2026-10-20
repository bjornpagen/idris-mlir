// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The literals of the scalar types of ours, and the names the printer gives
// a value of each type. A graded value takes its carrier's name, so a
// linear string is %s.

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

// A natural is never negative, which its type proves: the one place a
// natural's literal is said. It is written as a big's, and a negative one
// is no literal of it, which the op that holds it is refused for.
bool NatType::isLiteral(Attribute literal) const {
  auto big = dyn_cast<BigAttr>(literal);
  return big && !big.getValue().isNegative();
}

ParseResult NatType::parseLiteral(AsmParser &parser, Attribute &literal) const {
  return BigType::get(getContext()).parseLiteral(parser, literal);
}

void QType::getAsmName(OpAsmSetNameFn setNameFn) const {
  if (auto carrier = dyn_cast<OpAsmTypeInterface>(getValue()))
    carrier.getAsmName(setNameFn);
}

void WorldType::getAsmName(OpAsmSetNameFn setNameFn) const { setNameFn("w"); }
void StrType::getAsmName(OpAsmSetNameFn setNameFn) const { setNameFn("s"); }
void BigType::getAsmName(OpAsmSetNameFn setNameFn) const { setNameFn("n"); }
void NatType::getAsmName(OpAsmSetNameFn setNameFn) const { setNameFn("n"); }
void FnType::getAsmName(OpAsmSetNameFn setNameFn) const { setNameFn("f"); }
void LazyType::getAsmName(OpAsmSetNameFn setNameFn) const { setNameFn("lazy"); }
void idr::TokenType::getAsmName(OpAsmSetNameFn setNameFn) const { setNameFn("tok"); }
