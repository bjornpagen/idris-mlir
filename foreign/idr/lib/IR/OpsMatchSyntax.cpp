// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The custom directives of the matches' assembly formats (IdrMatchOps.td):
// the results' types, the cases of each match and the default, read and
// written as scf.index_switch's cases are. An idr.match case is a
// constructor's tag, written by its name in the scrutinee's data type
// (CtorRef, Symbols.h); an idr.match_lit key is a literal of the
// scrutinee's type, which the type reads (LiteralTypeInterface).

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Symbols.h"

#include "mlir/IR/OpImplementation.h"

#include <memory>

using namespace mlir;
using namespace idr;

namespace idr {

// `(R, ...)`, the results' types, none among them: a type directive over a
// list of types reads one type at least.
ParseResult parseResultTypes(OpAsmParser &parser, SmallVectorImpl<Type> &types) {
  return parser.parseCommaSeparatedList(OpAsmParser::Delimiter::Paren,
                                        [&] { return parser.parseType(types.emplace_back()); });
}

void printResultTypes(OpAsmPrinter &printer, Operation *, TypeRange types) {
  printer << '(';
  llvm::interleaveComma(types, printer);
  printer << ')';
}

// `case @C(%x: A, ...) {...}` per case, each region's arguments the
// constructor's fields.
ParseResult parseMatchCases(OpAsmParser &parser, Type scrutineeType, DenseI32ArrayAttr &cases,
                            SmallVectorImpl<std::unique_ptr<Region>> &caseRegions) {
  SmallVector<int32_t> tags;
  while (succeeded(parser.parseOptionalKeyword("case"))) {
    IntegerAttr tag;
    SmallVector<OpAsmParser::Argument> fields;
    if (parseCtorRef(parser, scrutineeType, tag) ||
        parser.parseArgumentList(fields, OpAsmParser::Delimiter::Paren, /*allowType=*/true) ||
        parser.parseRegion(*caseRegions.emplace_back(std::make_unique<Region>()), fields))
      return failure();
    tags.push_back(static_cast<int32_t>(tag.getInt()));
  }
  cases = parser.getBuilder().getDenseI32ArrayAttr(tags);
  return success();
}

void printMatchCases(OpAsmPrinter &printer, Operation *op, Type scrutineeType,
                     DenseI32ArrayAttr cases, MutableArrayRef<Region> caseRegions) {
  Builder builder(op->getContext());
  for (auto [tag, region] : llvm::zip(cases.asArrayRef(), caseRegions)) {
    printer.printNewline();
    printer << "case ";
    printCtorRef(printer, op, scrutineeType, builder.getI32IntegerAttr(tag));
    printer << '(';
    llvm::interleaveComma(region.getArguments(), printer,
                          [&](BlockArgument arg) { printer.printRegionArgument(arg); });
    printer << ") ";
    printer.printRegion(region, /*printEntryBlockArgs=*/false);
  }
}

// `case <literal> {...}` per key, a literal of the value read, whatever its
// view's grade. Only text can put a key on a type without literals, which
// its verifier would refuse too.
ParseResult parseLiteralCases(OpAsmParser &parser, Type scrutineeType, ArrayAttr &cases,
                              SmallVectorImpl<std::unique_ptr<Region>> &caseRegions) {
  Type type = unrestricted(scrutineeType);
  auto literals = dyn_cast<LiteralTypeInterface>(type);
  SmallVector<Attribute> keys;
  while (succeeded(parser.parseOptionalKeyword("case"))) {
    if (!literals)
      return parser.emitError(parser.getCurrentLocation(), "a literal match on ")
             << type << " has no keys";
    if (literals.parseLiteral(parser, keys.emplace_back()) ||
        parser.parseRegion(*caseRegions.emplace_back(std::make_unique<Region>())))
      return failure();
  }
  cases = parser.getBuilder().getArrayAttr(keys);
  return success();
}

void printLiteralCases(OpAsmPrinter &printer, Operation *, Type, ArrayAttr cases,
                       MutableArrayRef<Region> caseRegions) {
  for (auto [key, region] : llvm::zip(cases, caseRegions)) {
    printer.printNewline();
    printer << "case ";
    printer.printAttributeWithoutType(key);
    printer << ' ';
    printer.printRegion(region, /*printEntryBlockArgs=*/false);
  }
}

// `default(%d: T) {...}`, the region and the scrutinee it binds back, when
// the match has a default that runs; nothing for the empty default of an
// exhaustive idr.match. A missing idr.match_lit default is its region
// constraint's to refuse.
ParseResult parseDefaultCase(OpAsmParser &parser, Region &defaultRegion) {
  if (failed(parser.parseOptionalKeyword("default")))
    return success();
  SmallVector<OpAsmParser::Argument> args;
  return failure(
      parser.parseArgumentList(args, OpAsmParser::Delimiter::Paren, /*allowType=*/true) ||
      parser.parseRegion(defaultRegion, args));
}

void printDefaultCase(OpAsmPrinter &printer, Operation *, Region &defaultRegion) {
  if (defaultRegion.empty())
    return;
  printer.printNewline();
  printer << "default(";
  llvm::interleaveComma(defaultRegion.getArguments(), printer,
                        [&](BlockArgument arg) { printer.printRegionArgument(arg); });
  printer << ") ";
  printer.printRegion(defaultRegion, /*printEntryBlockArgs=*/false);
}

} // namespace idr
