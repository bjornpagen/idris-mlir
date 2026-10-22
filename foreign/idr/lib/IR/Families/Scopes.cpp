// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The small types and attributes of index scopes: a member of a
// declaration's own group (`!idr.self`), the sorts a scope binds
// (`#idr.index_binders`), the terms a call or a jump gives them
// (`#idr.index_args`) and an assumed equality (`#idr.equation`); each held
// as its arrays of nodes in its storage (FamilyStorage.h, and Types.cpp for
// the type), its key its sub-elements, and written as its terms and sorts
// are.

#include "idr/IR/Families/Families.h"
#include "idr/IR/Families/FamilyStorage.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/DialectImplementation.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;
using namespace idr;
using namespace idr::families;

//===----------------------------------------------------------------------===//
// The parameters, as their storages hold them
//===----------------------------------------------------------------------===//

ArrayRef<Sort> IndexBindersAttr::getSorts() const { return getImpl()->sorts; }
ArrayRef<TermNode> IndexArgsAttr::getTerms() const { return getImpl()->terms; }
uint64_t IndexArgsAttr::getCount() const { return getImpl()->count; }
ArrayRef<TermNode> EquationAttr::getLhs() const { return getImpl()->lhs; }
ArrayRef<TermNode> EquationAttr::getRhs() const { return getImpl()->rhs; }

//===----------------------------------------------------------------------===//
// Sorts in text
//===----------------------------------------------------------------------===//

void families::printSort(AsmPrinter &printer, const Sort &sort) {
  switch (sort.kind) {
  case SortKind::NatSort:
    printer << "nat";
    return;
  case SortKind::TypeSort:
    printer << "type";
    return;
  case SortKind::OpaqueSort:
    printer << "opaque";
    return;
  case SortKind::ScalarSort:
    printer.printType(cast<TypeAttr>(sort.payload).getValue());
    return;
  case SortKind::FamilySort:
    if (sort.payload)
      printer.printAttribute(sort.payload);
    else
      printer << "self";
    if (sort.member != 0)
      printer << " at " << sort.member;
    return;
  }
}

ParseResult families::parseSort(AsmParser &parser, Sort &sort) {
  sort = Sort{SortKind::OpaqueSort, 0, Attribute()};
  if (succeeded(parser.parseOptionalKeyword("nat"))) {
    sort.kind = SortKind::NatSort;
    return success();
  }
  if (succeeded(parser.parseOptionalKeyword("type"))) {
    sort.kind = SortKind::TypeSort;
    return success();
  }
  if (succeeded(parser.parseOptionalKeyword("opaque")))
    return success();
  auto member = [&]() -> ParseResult {
    if (succeeded(parser.parseOptionalKeyword("at")))
      return parser.parseInteger(sort.member);
    return success();
  };
  if (succeeded(parser.parseOptionalKeyword("self"))) {
    sort.kind = SortKind::FamilySort;
    return member();
  }
  Attribute group;
  OptionalParseResult attr = parser.parseOptionalAttribute(group);
  if (attr.has_value()) {
    if (failed(*attr))
      return failure();
    if (!isa<FamilyAttr>(group))
      return parser.emitError(parser.getCurrentLocation(), "expects a family, got ") << group;
    sort.kind = SortKind::FamilySort;
    sort.payload = group;
    return member();
  }
  Type scalar;
  if (parser.parseType(scalar))
    return failure();
  sort.kind = SortKind::ScalarSort;
  sort.payload = TypeAttr::get(scalar);
  return success();
}

//===----------------------------------------------------------------------===//
// The types and attributes in text
//===----------------------------------------------------------------------===//

// `!idr.self[v0]`, `!idr.self at 1 [v0]`: the member after `at` when it is
// not the first, its indices when it has any. Read only in a declaration,
// so a constructor of the group in its indices is not resolved here.
void SelfType::print(AsmPrinter &printer) const {
  if (getMember() != 0)
    printer << " at " << getMember();
  if (getIndices().empty())
    return;
  printer << '[';
  printTerms(printer, getIndices(), countTerms(getIndices()).value_or(0), Attribute());
  printer << ']';
}

Type SelfType::parse(AsmParser &parser) {
  uint32_t member = 0;
  if (succeeded(parser.parseOptionalKeyword("at")) && parser.parseInteger(member))
    return {};
  SmallVector<TermNode> indices;
  if (succeeded(parser.parseOptionalLSquare())) {
    do {
      if (parseTerm(parser, indices, nullptr))
        return {};
    } while (succeeded(parser.parseOptionalComma()));
    if (parser.parseRSquare())
      return {};
  }
  return get(parser.getContext(), member, indices);
}

void IndexBindersAttr::print(AsmPrinter &printer) const {
  printer << "<[";
  llvm::interleaveComma(getSorts(), printer, [&](const Sort &sort) { printSort(printer, sort); });
  printer << "]>";
}

Attribute IndexBindersAttr::parse(AsmParser &parser, Type) {
  SmallVector<Sort> sorts;
  if (parser.parseLess() ||
      parser.parseCommaSeparatedList(AsmParser::Delimiter::Square,
                                     [&]() { return parseSort(parser, sorts.emplace_back()); }) ||
      parser.parseGreater())
    return {};
  return get(parser.getContext(), sorts);
}

void IndexArgsAttr::print(AsmPrinter &printer) const {
  printer << "<[";
  printTerms(printer, getTerms(), getCount(), Attribute());
  printer << "]>";
}

Attribute IndexArgsAttr::parse(AsmParser &parser, Type) {
  SmallVector<TermNode> terms;
  uint64_t count = 0;
  if (parser.parseLess() ||
      parser.parseCommaSeparatedList(AsmParser::Delimiter::Square, [&]() {
        ++count;
        return parseTerm(parser, terms, nullptr);
      }) ||
      parser.parseGreater())
    return {};
  return get(parser.getContext(), terms, count);
}

void EquationAttr::print(AsmPrinter &printer) const {
  printer << '<';
  printTerm(printer, Term(getLhs()), Attribute());
  printer << " = ";
  printTerm(printer, Term(getRhs()), Attribute());
  printer << '>';
}

Attribute EquationAttr::parse(AsmParser &parser, Type) {
  SmallVector<TermNode> lhs, rhs;
  if (parser.parseLess() || parseTerm(parser, lhs, nullptr) || parser.parseEqual() ||
      parseTerm(parser, rhs, nullptr) || parser.parseGreater())
    return {};
  return get(parser.getContext(), lhs, rhs);
}
