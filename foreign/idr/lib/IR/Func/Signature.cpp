// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a signature says beyond its types: where each scoped parameter and
// result lives (`#idr.lives_in`), and what a function gives back of its
// arguments (`#idr.given_back`, each entry its own `#idr.given_back.entry`,
// whose storage owns its field positions). Their syntax, their bytecode
// values, their order, and the lookups a function and a call answer the
// lifetime of a scoped value by.

#include "idr/IR/Func.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/DialectImplementation.h"
#include "llvm/ADT/STLExtras.h"

#include <limits>

using namespace mlir;
using namespace idr;

//===----------------------------------------------------------------------===//
// Positions and entries in bytecode
//===----------------------------------------------------------------------===//

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

llvm::hash_code idr::hash_value(const LivesIn &entry) {
  return llvm::hash_combine(entry.value, entry.lifetime);
}

llvm::hash_code idr::hash_value(const Outlives &bound) {
  return llvm::hash_combine(bound.longer, bound.shorter);
}

LogicalResult idr::readLivesIn(DialectBytecodeReader &reader, LivesIn &entry) {
  return failure(failed(readPosition(reader, entry.value)) ||
                 failed(readPosition(reader, entry.lifetime)));
}

void idr::writeLivesIn(DialectBytecodeWriter &writer, const LivesIn &entry) {
  writePosition(writer, entry.value);
  writePosition(writer, entry.lifetime);
}

LogicalResult idr::readOutlives(DialectBytecodeReader &reader, Outlives &bound) {
  return failure(failed(readPosition(reader, bound.longer)) ||
                 failed(readPosition(reader, bound.shorter)));
}

void idr::writeOutlives(DialectBytecodeWriter &writer, const Outlives &bound) {
  writePosition(writer, bound.longer);
  writePosition(writer, bound.shorter);
}

LogicalResult idr::readGivenBackEntry(DialectBytecodeReader &reader, GivenBackEntryAttr &entry) {
  return reader.readAttribute(entry);
}

void idr::writeGivenBackEntry(DialectBytecodeWriter &writer, GivenBackEntryAttr entry) {
  writer.writeAttribute(entry);
}

//===----------------------------------------------------------------------===//
// #idr.lives_in
//===----------------------------------------------------------------------===//

namespace {

// `2 in 0`.
ParseResult parseLivesIn(AsmParser &parser, SmallVectorImpl<LivesIn> &entries) {
  LivesIn entry{};
  if (parser.parseInteger(entry.value) || parser.parseKeyword("in") ||
      parser.parseInteger(entry.lifetime))
    return failure();
  entries.push_back(entry);
  return success();
}

void printLivesIn(AsmPrinter &printer, ArrayRef<LivesIn> entries) {
  printer << '(';
  llvm::interleaveComma(entries, printer,
                        [&](const LivesIn &entry) { printer << entry.value << " in " << entry.lifetime; });
  printer << ')';
}

// The lifetime an entry of `entries`, sorted by the position each states a
// lifetime for, gives `position`.
std::optional<std::uint32_t> lookUp(ArrayRef<LivesIn> entries, std::uint32_t position) {
  const LivesIn *at = llvm::lower_bound(
      entries, position, [](const LivesIn &entry, std::uint32_t wanted) { return entry.value < wanted; });
  if (at == entries.end() || at->value != position)
    return std::nullopt;
  return at->lifetime;
}

// Each list increases by the position it states a lifetime for, so no
// value lives in two lifetimes and a lookup is a search.
LogicalResult increasing(function_ref<InFlightDiagnostic()> emitError, ArrayRef<LivesIn> entries,
                         StringRef what) {
  for (auto [before, after] : llvm::zip(entries, entries.drop_front()))
    if (before.value >= after.value)
      return emitError() << "lists " << what << " " << after.value << " after " << before.value
                         << ": positions increase, each once";
  return success();
}

} // namespace

// `<(2 in 0, 3 in 0) -> (0 in 0)>`, then ` where (0 >= 1)` when a bound is
// declared.
Attribute LivesInAttr::parse(AsmParser &parser, Type) {
  SmallVector<LivesIn> parameters, results;
  SmallVector<Outlives> bounds;
  auto bound = [&]() -> ParseResult {
    Outlives each{};
    if (parser.parseInteger(each.longer) || parser.parseGreater() || parser.parseEqual() ||
        parser.parseInteger(each.shorter))
      return failure();
    bounds.push_back(each);
    return success();
  };
  if (parser.parseLess() ||
      parser.parseCommaSeparatedList(AsmParser::Delimiter::Paren,
                                     [&] { return parseLivesIn(parser, parameters); }) ||
      parser.parseArrow() ||
      parser.parseCommaSeparatedList(AsmParser::Delimiter::Paren,
                                     [&] { return parseLivesIn(parser, results); }))
    return {};
  if (succeeded(parser.parseOptionalKeyword("where")) &&
      parser.parseCommaSeparatedList(AsmParser::Delimiter::Paren, bound))
    return {};
  if (parser.parseGreater())
    return {};
  return LivesInAttr::getChecked([&] { return parser.emitError(parser.getNameLoc()); },
                                 parser.getContext(), parameters, results, bounds);
}

void LivesInAttr::print(AsmPrinter &printer) const {
  printer << '<';
  printLivesIn(printer, getParameters());
  printer << " -> ";
  printLivesIn(printer, getResults());
  if (!getBounds().empty()) {
    printer << " where (";
    llvm::interleaveComma(getBounds(), printer, [&](const Outlives &bound) {
      printer << bound.longer << " >= " << bound.shorter;
    });
    printer << ')';
  }
  printer << '>';
}

// A bound relates two lifetimes: `a >= a` says nothing, and no value lives
// in two. That each position names what its signature has is the
// function's own rule, which holds the signature.
LogicalResult LivesInAttr::verify(function_ref<InFlightDiagnostic()> emitError,
                                  ArrayRef<LivesIn> parameters, ArrayRef<LivesIn> results,
                                  ArrayRef<Outlives> bounds) {
  if (failed(increasing(emitError, parameters, "parameter")) ||
      failed(increasing(emitError, results, "result")))
    return failure();
  for (const Outlives &bound : bounds)
    if (bound.longer == bound.shorter)
      return emitError() << "bounds lifetime parameter " << bound.longer << " by itself";
  return success();
}

std::optional<std::uint32_t> LivesInAttr::lifetimeOfParameter(std::uint32_t parameter) const {
  return lookUp(getParameters(), parameter);
}

std::optional<std::uint32_t> LivesInAttr::lifetimeOfResult(std::uint32_t result) const {
  return lookUp(getResults(), result);
}

//===----------------------------------------------------------------------===//
// #idr.given_back
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
