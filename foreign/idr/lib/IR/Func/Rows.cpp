// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A function's row: its forms as the IR holds it (text, a property's
// attribute, bytecode), by the hooks the specification declares; what LLVM
// is told of a function; and the function's check, which holds the row and
// the record to the one derivation of its body, the atoms spelled by the
// names the forms use.

#include "idr/Analysis/Effects.h"
#include "idr/IR/Func.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/Diagnostics.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/Support/raw_ostream.h"

#include <string>
#include <utility>

using namespace mlir;
using namespace idr;

//===----------------------------------------------------------------------===//
// The row, as the IR holds it
//===----------------------------------------------------------------------===//

namespace {

// An atom's printed name, from the effect system's generated table.
StringRef nameOf(effects::Atom atom) {
  return EnumTraits<effects::Atom>::names[static_cast<std::size_t>(std::to_underlying(atom))];
}

// The atoms a row holds, in their order.
auto atomsOf(effects::Row row) {
  static constexpr auto every = allOf<effects::Atom>();
  return llvm::make_filter_range(every, [row](effects::Atom atom) { return row.contains(atom); });
}

} // namespace

// A row's form in the generic syntax and a property dictionary: its atoms'
// names, in the order the effect system lists them.
Attribute idr::convertRowToAttribute(MLIRContext *context, effects::Row row) {
  SmallVector<Attribute> names;
  for (effects::Atom atom : atomsOf(row))
    names.push_back(StringAttr::get(context, nameOf(atom)));
  return ArrayAttr::get(context, names);
}

// Text read at the boundary: each name is matched once against the
// table's, and the row holds the atoms from there on.
LogicalResult idr::convertRowFromAttribute(effects::Row &row, Attribute attribute,
                                           function_ref<InFlightDiagnostic()> emitError) {
  auto names = dyn_cast<ArrayAttr>(attribute);
  if (!names)
    return emitError() << "expected a row, the list of its atoms' names";
  static constexpr auto every = allOf<effects::Atom>();
  effects::Row read;
  for (Attribute name : names) {
    auto text = dyn_cast<StringAttr>(name);
    auto atom =
        text ? llvm::find_if(every,
                             [&](effects::Atom candidate) { return nameOf(candidate) == text.getValue(); })
             : every.end();
    if (atom == every.end())
      return emitError() << name << " is no atom of a row";
    read = read | effects::Row{*atom};
  }
  row = read;
  return success();
}

llvm::hash_code idr::hashRow(effects::Row row) {
  SmallVector<unsigned> numbers;
  for (effects::Atom atom : atomsOf(row))
    numbers.push_back(static_cast<unsigned>(std::to_underlying(atom)));
  return llvm::hash_combine_range(numbers);
}

// In bytecode: how many atoms, then each one's number.
void idr::writeRow(DialectBytecodeWriter &writer, effects::Row row) {
  writer.writeVarInt(row.size());
  for (effects::Atom atom : atomsOf(row))
    writer.writeVarInt(static_cast<std::uint64_t>(std::to_underlying(atom)));
}

LogicalResult idr::readRow(DialectBytecodeReader &reader, effects::Row &row) {
  std::uint64_t count = 0;
  if (failed(reader.readVarInt(count)))
    return failure();
  effects::Row read;
  for (std::uint64_t at = 0; at < count; ++at) {
    std::uint64_t number = 0;
    if (failed(reader.readVarInt(number)))
      return failure();
    if (number >= EnumTraits<effects::Atom>::count)
      return reader.emitError() << "atom " << number << " is no atom of a row";
    read = read | effects::Row{static_cast<effects::Atom>(number)};
  }
  row = read;
  return success();
}

//===----------------------------------------------------------------------===//
// What LLVM is told
//===----------------------------------------------------------------------===//

// A write through a parameter is argument memory written, which the row's
// atoms do not hold: the record says it wherever it lists fewer untouched
// parameters than admit a write part.
effects::Told rows::told(FuncOp fn) {
  effects::Told facts = effects::told(fn.getRow());
  std::size_t untouched = 0;
  if (DenseI32ArrayAttr listed = fn.getUntouchedAttr())
    untouched = listed.size();
  if (ParameterParts(fn.getArgumentTypes()).writable() > untouched)
    facts = effects::withParameterWrite(facts);
  return facts;
}

//===----------------------------------------------------------------------===//
// The function's check
//===----------------------------------------------------------------------===//

namespace {

// The atoms of `row`, as the row prints them.
std::string spell(effects::Row row) {
  std::string text;
  llvm::raw_string_ostream out(text);
  llvm::interleaveComma(atomsOf(row), out, [&](effects::Atom atom) { out << nameOf(atom); });
  return text;
}

// What the function says it puts into each put parameter: its bound, or
// none.
llvm::SmallVector<Amount, 2> declaredPuts(FuncOp fn) {
  llvm::SmallVector<Amount, 2> declared(ParameterParts(fn.getArgumentTypes()).puttable(),
                                        Amount::unbounded());
  if (PutBoundsAttr bounded = fn.getBoundedAttr())
    for (const PutBound &bound : bounded.getBounds())
      declared[bound.parameter] = Amount::finite(bound.bytes);
  return declared;
}

} // namespace

rows::Check::Check(FuncOp fn)
    : fn(fn), derivation(fn, copies), row(fn.getRow()), bounds(declaredPuts(fn)) {
  if (DenseI32ArrayAttr listed = fn.getUntouchedAttr())
    untouched = listed.asArrayRef();
}

// Idris's proof is read before the body: the row of a function it did not
// prove holds divergence before any op adds to it.
LogicalResult rows::Check::enter(Operation *op, Region &region) {
  (void)derivation.enter(op, region);
  if (op != fn.getOperation())
    return success();
  if (effects::Row missing = derivation.state().sofar().atoms - row; !missing.empty())
    return fn.emitOpError("holds effects<")
           << spell(row) << ">, which lack " << spell(missing)
           << ": Idris did not prove its loops end";
  return success();
}

LogicalResult rows::Check::check(Operation *op) {
  (void)derivation.check(op);
  return covered(*op);
}

// The atoms, writes and amounts only grow as the walk goes on, so the
// first op after which one exceeds what the function says is the op that
// needs it.
LogicalResult rows::Check::covered(Operation &by) {
  const Derived &sofar = derivation.state().sofar();
  auto blame = [&](InFlightDiagnostic diag) -> LogicalResult {
    diag.attachNote(by.getLoc()) << "'" << by.getName() << "' needs it";
    return diag;
  };
  if (effects::Row missing = sofar.atoms - row; !missing.empty())
    return blame(fn.emitOpError("holds effects<") << spell(row) << ">, which lack "
                                                  << spell(missing));
  for (std::int32_t position : untouched)
    if (sofar.written.test(static_cast<unsigned>(position)))
      return blame(fn.emitOpError("lists its write-admitting parameter ")
                   << position << " untouched, which its body writes through");
  for (auto [position, put] : llvm::enumerate(sofar.puts))
    if (!put.within(bounds[position]))
      return blame(fn.emitOpError("bounds what it puts into its put parameter ")
                   << position << ", which its body exceeds");
  return success();
}
