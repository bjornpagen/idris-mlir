// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The index term each unknown axis of a function's signature is
// (`#idr.extents`, each entry its own `#idr.extent`, whose storage owns its
// term's nodes): their syntax, what each entry and the list hold of
// themselves, and how an edit of the signature moves them. What an entry
// names of the signature and of the binders is the function's verifier's.
// Their bytecode is printed from their wires; the entries' list is
// written with the hooks the specification declares.

#include "idr/IR/Func.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/DialectImplementation.h"
#include "llvm/ADT/STLExtras.h"

#include <cstddef>
#include <cstdint>
#include <optional>

using namespace mlir;
using namespace idr;

//===----------------------------------------------------------------------===//
// #idr.extent
//===----------------------------------------------------------------------===//

namespace {

// The axis an entry names, read without walking its term.
ExtentAt axisOf(ExtentAttr entry) {
  return {entry.getSide(), entry.getPosition(), entry.getAxis()};
}

// `input 0 axis 1 = v0`: the side as the specification spells it, the
// position on that side, the axis, then the term as the families write
// one.
ExtentAttr parseEntry(AsmParser &parser) {
  SMLoc loc = parser.getCurrentLocation();
  StringRef keyword;
  if (parser.parseKeyword(&keyword))
    return {};
  std::optional<ExtentSide> side = symbolizeExtentSide(keyword);
  if (!side) {
    parser.emitError(loc, "expected the side of a signature, got `") << keyword << "`";
    return {};
  }
  std::uint32_t position = 0;
  std::uint32_t axis = 0;
  SmallVector<families::TermNode> term;
  if (parser.parseInteger(position) || parser.parseKeyword("axis") || parser.parseInteger(axis) ||
      parser.parseEqual() || families::parseTerm(parser, term, nullptr))
    return {};
  return ExtentAttr::getChecked([&] { return parser.emitError(loc); }, parser.getContext(), *side,
                                position, axis, term);
}

void printEntry(AsmPrinter &printer, ExtentAttr entry) {
  printer << stringifyExtentSide(entry.getSide()) << ' ' << entry.getPosition() << " axis "
          << entry.getAxis() << " = ";
  families::printTerm(printer, families::Term(entry.getTerm()), Attribute());
}

} // namespace

Extent ExtentAttr::extent() const { return {axisOf(*this), families::Term(getTerm())}; }

Attribute ExtentAttr::parse(AsmParser &parser, Type) {
  if (parser.parseLess())
    return {};
  ExtentAttr entry = parseEntry(parser);
  if (!entry || parser.parseGreater())
    return {};
  return entry;
}

void ExtentAttr::print(AsmPrinter &printer) const {
  printer << '<';
  printEntry(printer, *this);
  printer << '>';
}

// One whole term, since a bytecode read writes nodes no builder wrote and
// every walk of the term trusts its extent; and one that names a binder,
// since a term naming none is a constant, whose axis the type makes
// static, or opaque, which names no size: either way the axis has no
// entry.
LogicalResult ExtentAttr::verify(function_ref<InFlightDiagnostic()> emitError, ExtentSide,
                                 std::uint32_t, std::uint32_t,
                                 ArrayRef<families::TermNode> term) {
  if (families::countTerms(term) != std::optional<std::size_t>(1))
    return emitError() << "expects one index term";
  if (families::freeLevelsOf(term) == 0)
    return emitError() << "names an axis by a term over no binder: a constant's axis is "
                          "static, and an opaque term names no size";
  return success();
}

//===----------------------------------------------------------------------===//
// #idr.extents
//===----------------------------------------------------------------------===//

// Each entry copies its term's nodes into its own storage, so the terms a
// writer or a substitution made may live anywhere until this returns.
ExtentsAttr ExtentsAttr::get(MLIRContext *context, ArrayRef<Extent> entries) {
  SmallVector<ExtentAttr> made;
  made.reserve(entries.size());
  for (const Extent &entry : entries)
    made.push_back(ExtentAttr::get(context, entry.at.side, entry.at.position, entry.at.axis,
                                   entry.term.nodes()));
  return get(context, ArrayRef<ExtentAttr>(made));
}

// Every entry at the position the signature's edit moves its value to, one
// whose value is erased gone with it; a position inserted has none, so its
// axes are named by no term until a writer names them. Positions move in order
// on each side, so the entries stay sorted, and the terms are over the
// binders, which no edit of the signature changes.
ExtentsAttr ExtentsAttr::renumber(ArrayRef<std::optional<std::uint32_t>> parameters,
                                  ArrayRef<std::optional<std::uint32_t>> results) const {
  SmallVector<Extent> kept;
  for (ExtentAttr attr : getEntries()) {
    Extent entry = attr.extent();
    if (std::optional<std::uint32_t> moved = onSide(entry.at.side, parameters, results)[entry.at.position])
      kept.push_back({{entry.at.side, *moved, entry.at.axis}, entry.term});
  }
  return get(getContext(), kept);
}

// The entries' text, `[input 0 axis 1 = v0, result 0 axis 0 = v0 + 1]`,
// each without its own name.
FailureOr<SmallVector<ExtentAttr>> idr::parseExtentEntries(AsmParser &parser) {
  SmallVector<ExtentAttr> entries;
  auto one = [&]() -> ParseResult {
    ExtentAttr entry = parseEntry(parser);
    if (!entry)
      return failure();
    entries.push_back(entry);
    return success();
  };
  if (parser.parseCommaSeparatedList(AsmParser::Delimiter::Square, one))
    return failure();
  return entries;
}

void idr::printExtentEntries(AsmPrinter &printer, ArrayRef<ExtentAttr> entries) {
  printer << '[';
  llvm::interleaveComma(entries, printer, [&](ExtentAttr entry) { printEntry(printer, entry); });
  printer << ']';
}

// Sorted by the axis each names, each axis once: an axis is one term, and a
// reader comparing two functions' lists walks both once. The order reads
// each entry's axis alone, not its term.
LogicalResult ExtentsAttr::verify(function_ref<InFlightDiagnostic()> emitError,
                                  ArrayRef<ExtentAttr> entries) {
  for (auto [before, after] : llvm::zip(entries, entries.drop_front()))
    if (!(axisOf(before) < axisOf(after)))
      return emitError() << "names an axis out of order, or twice";
  return success();
}
