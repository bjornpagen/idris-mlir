// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Where a signature's scoped parameters and results live, and the bounds
// between its lifetimes (`#idr.lives_in`): their syntax (their bytecode is
// printed from their wires), their order, the lookups a function and a call
// answer the lifetime of a scoped value by, restating one value's lifetime,
// and how an edit of the signature moves them.

#include "idr/IR/Func.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/DialectImplementation.h"
#include "llvm/ADT/STLExtras.h"

#include <concepts>
#include <cstdint>
#include <optional>
#include <type_traits>
#include <utility>

using namespace mlir;
using namespace idr;

//===----------------------------------------------------------------------===//
// Entries and bounds as values
//===----------------------------------------------------------------------===//

llvm::hash_code idr::hash_value(const LivesIn &entry) {
  return llvm::hash_combine(entry.value, entry.lifetime);
}

llvm::hash_code idr::hash_value(const Outlives &bound) {
  return llvm::hash_combine(bound.longer, bound.shorter);
}

// The entries' text, `(2 in 0, 3 in 0)`; their bytecode is their wire's.
FailureOr<SmallVector<LivesIn>> idr::parseLivesInEntries(AsmParser &parser) {
  SmallVector<LivesIn> entries;
  if (parser.parseCommaSeparatedList(AsmParser::Delimiter::Paren, [&]() -> ParseResult {
        LivesIn entry{};
        if (parser.parseInteger(entry.value) || parser.parseKeyword("in") ||
            parser.parseInteger(entry.lifetime))
          return failure();
        entries.push_back(entry);
        return success();
      }))
    return failure();
  return entries;
}

void idr::printLivesInEntries(AsmPrinter &printer, ArrayRef<LivesIn> entries) {
  printer << '(';
  llvm::interleaveComma(entries, printer,
                        [&](LivesIn entry) { printer << entry.value << " in " << entry.lifetime; });
  printer << ')';
}

// The bounds' text, `(0 >= 1)`; their bytecode is their wire's.
FailureOr<SmallVector<Outlives>> idr::parseOutlivesBounds(AsmParser &parser) {
  SmallVector<Outlives> bounds;
  if (parser.parseCommaSeparatedList(AsmParser::Delimiter::Paren, [&]() -> ParseResult {
        Outlives bound{};
        if (parser.parseInteger(bound.longer) || parser.parseGreater() || parser.parseEqual() ||
            parser.parseInteger(bound.shorter))
          return failure();
        bounds.push_back(bound);
        return success();
      }))
    return failure();
  return bounds;
}

void idr::printOutlivesBounds(AsmPrinter &printer, ArrayRef<Outlives> bounds) {
  printer << '(';
  llvm::interleaveComma(bounds, printer, [&](const Outlives &bound) {
    printer << bound.longer << " >= " << bound.shorter;
  });
  printer << ')';
}

//===----------------------------------------------------------------------===//
// #idr.lives_in
//===----------------------------------------------------------------------===//

namespace {

// The lifetime an entry of `entries`, sorted by the position each states a
// lifetime for, gives `position`.
std::optional<std::uint32_t> lookUp(ArrayRef<LivesIn> entries, std::uint32_t position) {
  const LivesIn *at = llvm::lower_bound(
      entries, position, [](const LivesIn &entry, std::uint32_t wanted) { return entry.value < wanted; });
  if (at == entries.end() || at->value != position)
    return std::nullopt;
  return at->lifetime;
}

// `entries`, sorted by the position each states a lifetime for, with
// `position` stated to live in `lifetime`, or in none: its entry made,
// replaced or gone, the order kept.
SmallVector<LivesIn> restated(ArrayRef<LivesIn> entries, std::uint32_t position,
                              std::optional<std::uint32_t> lifetime) {
  SmallVector<LivesIn> out(entries);
  LivesIn *at = llvm::lower_bound(
      out, position, [](const LivesIn &entry, std::uint32_t wanted) { return entry.value < wanted; });
  bool listed = at != out.end() && at->value == position;
  if (lifetime && listed)
    at->lifetime = *lifetime;
  else if (lifetime)
    out.insert(at, LivesIn{position, *lifetime});
  else if (listed)
    out.erase(at);
  return out;
}

// The statement of three lists; none when all three are empty, so a
// statement emptied by restating or erasing is absent, as one a signature
// with no scoped value and no bound never had.
LivesInAttr statement(MLIRContext *context, ArrayRef<LivesIn> parameters,
                      ArrayRef<LivesIn> results, ArrayRef<Outlives> bounds) {
  if (parameters.empty() && results.empty() && bounds.empty())
    return {};
  return LivesInAttr::get(context, parameters, results, bounds);
}

// Each list increases by the position it states a lifetime for, so no
// value lives in two lifetimes and a lookup is a search. `emitError` opens
// the diagnostic of whoever verifies the list.
template <std::invocable<> EmitError>
  requires std::same_as<std::invoke_result_t<EmitError &>, InFlightDiagnostic>
LogicalResult increasing(EmitError &&emitError, ArrayRef<LivesIn> entries, StringRef what) {
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
  if (parser.parseLess())
    return {};
  FailureOr<SmallVector<LivesIn>> parameters = parseLivesInEntries(parser);
  if (failed(parameters) || parser.parseArrow())
    return {};
  FailureOr<SmallVector<LivesIn>> results = parseLivesInEntries(parser);
  if (failed(results))
    return {};
  SmallVector<Outlives> bounds;
  if (succeeded(parser.parseOptionalKeyword("where"))) {
    FailureOr<SmallVector<Outlives>> declared = parseOutlivesBounds(parser);
    if (failed(declared))
      return {};
    bounds = std::move(*declared);
  }
  if (parser.parseGreater())
    return {};
  // The lists as the generated builder takes them, whose body sees the
  // storage, rather than as the base's template would deduce them, which
  // would need the storage here.
  return LivesInAttr::getChecked([&] { return parser.emitError(parser.getNameLoc()); },
                                 parser.getContext(), ArrayRef<LivesIn>(*parameters),
                                 ArrayRef<LivesIn>(*results), ArrayRef<Outlives>(bounds));
}

void LivesInAttr::print(AsmPrinter &printer) const {
  printer << '<';
  printLivesInEntries(printer, getParameters());
  printer << " -> ";
  printLivesInEntries(printer, getResults());
  if (!getBounds().empty()) {
    printer << " where ";
    printOutlivesBounds(printer, getBounds());
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

// What a function or a call states of its scoped values, absent when it
// states none, with one parameter's or one result's lifetime stated anew:
// a position in the signature, or none for a value no longer scoped.
LivesInAttr LivesInAttr::restateParameter(MLIRContext *context, LivesInAttr lives,
                                          std::uint32_t parameter,
                                          std::optional<std::uint32_t> lifetime) {
  if (!lives)
    return statement(context, restated({}, parameter, lifetime), {}, {});
  return statement(context, restated(lives.getParameters(), parameter, lifetime),
                   lives.getResults(), lives.getBounds());
}

LivesInAttr LivesInAttr::restateResult(MLIRContext *context, LivesInAttr lives,
                                       std::uint32_t result,
                                       std::optional<std::uint32_t> lifetime) {
  if (!lives)
    return statement(context, {}, restated({}, result, lifetime), {});
  return statement(context, lives.getParameters(), restated(lives.getResults(), result, lifetime),
                   lives.getBounds());
}

//===----------------------------------------------------------------------===//
// Moved by an edit of the signature
//===----------------------------------------------------------------------===//

namespace {

// Each entry of `entries` at the position `values` gives its value and
// `lifetimes` its lifetime, one whose value goes gone with it; a value kept
// whose lifetime goes would live in none, so there is no list to give.
LogicalResult moveEntries(ArrayRef<LivesIn> entries, ArrayRef<std::optional<std::uint32_t>> values,
                          ArrayRef<std::optional<std::uint32_t>> lifetimes,
                          SmallVectorImpl<LivesIn> &moved) {
  for (LivesIn entry : entries) {
    std::optional<std::uint32_t> value = values[entry.value];
    if (!value)
      continue;
    std::optional<std::uint32_t> lifetime = lifetimes[entry.lifetime];
    if (!lifetime)
      return failure();
    moved.push_back({*value, *lifetime});
  }
  return success();
}

// The bounds between the lifetime parameters `to` keeps, at their new
// positions. Each one erased is taken out in turn, every bound into it
// joined to every bound out of it, so a chain through erased lifetimes
// still bounds its two ends; each bound once, and none of a lifetime by
// itself. What is left names only lifetimes kept.
SmallVector<Outlives> movedBounds(ArrayRef<Outlives> bounds, ArrayRef<std::optional<std::uint32_t>> to) {
  SmallVector<Outlives> left(bounds);
  for (std::uint32_t gone = 0; gone < to.size(); ++gone) {
    if (to[gone])
      continue;
    SmallVector<std::uint32_t> longer, shorter;
    for (const Outlives &bound : left) {
      if (bound.shorter == gone)
        longer.push_back(bound.longer);
      if (bound.longer == gone)
        shorter.push_back(bound.shorter);
    }
    llvm::erase_if(left, [&](const Outlives &bound) { return bound.longer == gone || bound.shorter == gone; });
    for (std::uint32_t outer : longer)
      for (std::uint32_t inner : shorter)
        if (Outlives joined{outer, inner}; outer != inner && !llvm::is_contained(left, joined))
          left.push_back(joined);
  }
  SmallVector<Outlives> moved;
  for (const Outlives &bound : left)
    moved.push_back({*to[bound.longer], *to[bound.shorter]});
  return moved;
}

} // namespace

// Every entry at the positions the signature's edit moves its value and its
// lifetime to, and every bound kept between the lifetimes it keeps: one
// rule for inserting and erasing parameters and results alike. Both lists
// move in order, so each still increases.
FailureOr<LivesInAttr> LivesInAttr::renumber(ArrayRef<std::optional<std::uint32_t>> parameters,
                                             ArrayRef<std::optional<std::uint32_t>> results) const {
  SmallVector<LivesIn> scopedParameters, scopedResults;
  if (failed(moveEntries(getParameters(), parameters, parameters, scopedParameters)) ||
      failed(moveEntries(getResults(), results, parameters, scopedResults)))
    return failure();
  return statement(getContext(), scopedParameters, scopedResults, movedBounds(getBounds(), parameters));
}
