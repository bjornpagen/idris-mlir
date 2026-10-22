// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a function gives back of its arguments (`#idr.given_back`, each
// entry its own `#idr.given_back.entry`, whose storage owns its field
// positions): their syntax, their bytecode values, their order, and how an
// edit of the signature moves them. A position in a signature or a
// constructor, which every positional value of a signature is written
// with in bytecode, is this attribute's own value.

#include "idr/IR/Func.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/DialectImplementation.h"
#include "llvm/ADT/STLExtras.h"

#include <cstdint>
#include <limits>
#include <optional>

using namespace mlir;
using namespace idr;

//===----------------------------------------------------------------------===//
// Positions and entries in bytecode
//===----------------------------------------------------------------------===//

// A position in a signature or a constructor, as an unsigned word.
LogicalResult idr::readPosition(DialectBytecodeReader &reader, std::uint32_t &position) {
  std::uint64_t word = 0;
  if (failed(reader.readVarInt(word)))
    return failure();
  if (word > std::numeric_limits<std::uint32_t>::max())
    return reader.emitError() << "position " << word << " out of range";
  position = static_cast<std::uint32_t>(word);
  return success();
}

void idr::writePosition(DialectBytecodeWriter &writer, std::uint32_t position) {
  writer.writeVarInt(position);
}

// An entry of `#idr.given_back`, as the attribute it is.
LogicalResult idr::readGivenBackEntry(DialectBytecodeReader &reader, GivenBackEntryAttr &entry) {
  return reader.readAttribute(entry);
}

void idr::writeGivenBackEntry(DialectBytecodeWriter &writer, GivenBackEntryAttr entry) {
  writer.writeAttribute(entry);
}

//===----------------------------------------------------------------------===//
// #idr.given_back.entry
//===----------------------------------------------------------------------===//

namespace {

// `1[0, 2]`, or `1` for the whole value.
ParseResult parsePath(AsmParser &parser, std::uint32_t &index, SmallVectorImpl<std::uint32_t> &fields) {
  if (parser.parseInteger(index))
    return failure();
  if (failed(parser.parseOptionalLSquare()))
    return success();
  if (parser.parseCommaSeparatedList([&]() -> ParseResult {
        std::uint32_t field = 0;
        if (parser.parseInteger(field))
          return failure();
        fields.push_back(field);
        return success();
      }))
    return failure();
  return parser.parseRSquare();
}

void printPath(AsmPrinter &printer, const GivenBackPath &path) {
  printer << path.index;
  if (path.fields.empty())
    return;
  printer << '[';
  llvm::interleaveComma(path.fields, printer);
  printer << ']';
}

// `1[0] <- 0[1]`.
GivenBackEntryAttr parseEntry(AsmParser &parser) {
  std::uint32_t result = 0, argument = 0;
  SmallVector<std::uint32_t> resultFields, argumentFields;
  if (parsePath(parser, result, resultFields) || parser.parseLess() || parser.parseMinus() ||
      parsePath(parser, argument, argumentFields))
    return {};
  return GivenBackEntryAttr::get(parser.getContext(), result, resultFields, argument,
                                 argumentFields);
}

void printEntry(AsmPrinter &printer, GivenBackEntryAttr entry) {
  GivenBackEntry each = entry.entry();
  printPath(printer, each.result);
  printer << " <- ";
  printPath(printer, each.argument);
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

// `<[0 <- 2, 1[0] <- 0[1]]>`.
Attribute GivenBackAttr::parse(AsmParser &parser, Type) {
  SmallVector<GivenBackEntryAttr> entries;
  auto one = [&]() -> ParseResult {
    GivenBackEntryAttr entry = parseEntry(parser);
    if (!entry)
      return failure();
    entries.push_back(entry);
    return success();
  };
  if (parser.parseLess() || parser.parseCommaSeparatedList(AsmParser::Delimiter::Square, one) ||
      parser.parseGreater())
    return {};
  return GivenBackAttr::getChecked([&] { return parser.emitError(parser.getNameLoc()); },
                                   parser.getContext(), entries);
}

void GivenBackAttr::print(AsmPrinter &printer) const {
  printer << "<[";
  llvm::interleaveComma(getEntries(), printer,
                        [&](GivenBackEntryAttr entry) { printEntry(printer, entry); });
  printer << "]>";
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
