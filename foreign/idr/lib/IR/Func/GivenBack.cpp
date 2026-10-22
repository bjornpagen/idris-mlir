// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a function gives back of its arguments (`#idr.given_back`, each
// entry its own `#idr.given_back.entry`, whose storage owns its field
// positions): their syntax, their order, and how an edit of the signature
// moves them. Their bytecode is printed from their wires; their text is
// the hooks the specification declares, which an entry's path and the
// entries' list are written with.

#include "idr/IR/Func.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/DialectImplementation.h"
#include "llvm/ADT/STLExtras.h"

#include <cstdint>
#include <optional>

using namespace mlir;
using namespace idr;

//===----------------------------------------------------------------------===//
// Paths
//===----------------------------------------------------------------------===//

// A position in a signature, `1`.
FailureOr<std::uint32_t> idr::parsePosition(AsmParser &parser) {
  std::uint32_t position = 0;
  if (parser.parseInteger(position))
    return failure();
  return position;
}

void idr::printPosition(AsmPrinter &printer, std::uint32_t position) { printer << position; }

// The fields down to a component, `[0, 2]`, or nothing for the whole value.
FailureOr<SmallVector<std::uint32_t>> idr::parseFieldPath(AsmParser &parser) {
  SmallVector<std::uint32_t> fields;
  if (failed(parser.parseOptionalLSquare()))
    return fields;
  if (parser.parseCommaSeparatedList([&]() -> ParseResult {
        std::uint32_t field = 0;
        if (parser.parseInteger(field))
          return failure();
        fields.push_back(field);
        return success();
      }) ||
      parser.parseRSquare())
    return failure();
  return fields;
}

void idr::printFieldPath(AsmPrinter &printer, ArrayRef<std::uint32_t> fields) {
  if (fields.empty())
    return;
  printer << '[';
  llvm::interleaveComma(fields, printer);
  printer << ']';
}

//===----------------------------------------------------------------------===//
// #idr.given_back.entry
//===----------------------------------------------------------------------===//

namespace {

// `1[0] <- 0[1]`.
GivenBackEntryAttr parseEntry(AsmParser &parser) {
  FailureOr<std::uint32_t> result = parsePosition(parser);
  if (failed(result))
    return {};
  FailureOr<SmallVector<std::uint32_t>> resultFields = parseFieldPath(parser);
  if (failed(resultFields) || parser.parseLess() || parser.parseMinus())
    return {};
  FailureOr<std::uint32_t> argument = parsePosition(parser);
  if (failed(argument))
    return {};
  FailureOr<SmallVector<std::uint32_t>> argumentFields = parseFieldPath(parser);
  if (failed(argumentFields))
    return {};
  return GivenBackEntryAttr::get(parser.getContext(), *result, *resultFields, *argument,
                                 *argumentFields);
}

void printEntry(AsmPrinter &printer, GivenBackEntryAttr entry) {
  printPosition(printer, entry.getResult());
  printFieldPath(printer, entry.getResultFields());
  printer << " <- ";
  printPosition(printer, entry.getArgument());
  printFieldPath(printer, entry.getArgumentFields());
}

} // namespace

GivenBackEntry GivenBackEntryAttr::entry() const {
  return {{getResult(), getResultFields()}, {getArgument(), getArgumentFields()}};
}

Attribute GivenBackEntryAttr::parse(AsmParser &parser, Type) {
  if (parser.parseLess())
    return {};
  GivenBackEntryAttr entry = parseEntry(parser);
  if (!entry || parser.parseGreater())
    return {};
  return entry;
}

void GivenBackEntryAttr::print(AsmPrinter &printer) const {
  printer << '<';
  printEntry(printer, *this);
  printer << '>';
}

//===----------------------------------------------------------------------===//
// #idr.given_back
//===----------------------------------------------------------------------===//

// Each entry copies its field positions into its own storage, so the
// optimizer's paths may live anywhere until this returns.
GivenBackAttr GivenBackAttr::get(MLIRContext *context, ArrayRef<GivenBackEntry> entries) {
  SmallVector<GivenBackEntryAttr> made;
  made.reserve(entries.size());
  for (const GivenBackEntry &entry : entries)
    made.push_back(GivenBackEntryAttr::get(context, entry.result.index, entry.result.fields,
                                           entry.argument.index, entry.argument.fields));
  return get(context, ArrayRef<GivenBackEntryAttr>(made));
}

// Every entry at the positions the signature's edit moves its result and
// its argument to, one whose result or argument goes gone with it, and none
// when nothing is left. Results move in order, so the entries stay sorted.
GivenBackAttr GivenBackAttr::renumber(ArrayRef<std::optional<std::uint32_t>> parameters,
                                      ArrayRef<std::optional<std::uint32_t>> results) const {
  SmallVector<GivenBackEntry> kept;
  for (GivenBackEntryAttr attr : getEntries()) {
    GivenBackEntry entry = attr.entry();
    std::optional<std::uint32_t> result = results[entry.result.index];
    std::optional<std::uint32_t> argument = parameters[entry.argument.index];
    if (result && argument)
      kept.push_back({{*result, entry.result.fields}, {*argument, entry.argument.fields}});
  }
  if (kept.empty())
    return {};
  return get(getContext(), kept);
}

// The entries' text, `[0 <- 2, 1[0] <- 0[1]]`, each without its own name.
FailureOr<SmallVector<GivenBackEntryAttr>> idr::parseGivenBackEntries(AsmParser &parser) {
  SmallVector<GivenBackEntryAttr> entries;
  auto one = [&]() -> ParseResult {
    GivenBackEntryAttr entry = parseEntry(parser);
    if (!entry)
      return failure();
    entries.push_back(entry);
    return success();
  };
  if (parser.parseCommaSeparatedList(AsmParser::Delimiter::Square, one))
    return failure();
  return entries;
}

void idr::printGivenBackEntries(AsmPrinter &printer, ArrayRef<GivenBackEntryAttr> entries) {
  printer << '[';
  llvm::interleaveComma(entries, printer, [&](GivenBackEntryAttr entry) { printEntry(printer, entry); });
  printer << ']';
}

// Sorted by result path, each once: a result component is one argument
// component, and a reader comparing two functions' lists walks both once.
LogicalResult GivenBackAttr::verify(function_ref<InFlightDiagnostic()> emitError,
                                    ArrayRef<GivenBackEntryAttr> entries) {
  for (auto [before, after] : llvm::zip(entries, entries.drop_front()))
    if (!(before.entry().result < after.entry().result))
      return emitError() << "lists a result component out of order, or twice";
  return success();
}
