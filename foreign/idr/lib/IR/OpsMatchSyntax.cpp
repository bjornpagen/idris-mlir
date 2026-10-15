// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The syntax of idr.match and idr.match_lit: a head they share, then a case
// per key and a default. An idr.match case is a constructor's tag, written
// by its name in the scrutinee's data type (CtorRef, Symbols.h), which the
// head has read. Apart from the matches' rules, which would push that unit
// past its size.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"

#include "mlir/IR/OpImplementation.h"

using namespace mlir;
using namespace idr;

namespace {

// The attribute dictionary of a match, whose cases its syntax spells: a
// `cases` in the dictionary would become that property when the op is
// created, silently in place of the clauses' keys. Check the dictionary's
// inherent facts first, as the generic parser does, and refuse a restated
// one.
ParseResult parseAttrs(OpAsmParser &parser, OperationState &result,
                       ArrayRef<StringRef> spelled) {
  SMLoc loc = parser.getCurrentLocation();
  if (parser.parseOptionalAttrDictWithKeyword(result.attributes))
    return failure();
  std::optional<RegisteredOperationName> info = result.name.getRegisteredInfo();
  if (info && failed(info->verifyInherentAttrs(result.attributes,
                                               [&]() { return parser.emitError(loc); })))
    return failure();
  for (StringRef name : spelled)
    if (result.attributes.get(name))
      return parser.emitError(loc, "inherent attribute '")
             << name << "' cannot be parsed from attr-dict when strict properties in assembly "
             << "format is enabled";
  return success();
}

//===----------------------------------------------------------------------===//
// Matches
//===----------------------------------------------------------------------===//

// Parses `{ case <key> <region> ... default[(<args>)] <region> }`;
// `parseCase` parses a key and its region.
ParseResult parseMatchBody(OpAsmParser &parser, OperationState &result,
                           function_ref<ParseResult(Region &)> parseCase) {
  if (parser.parseLBrace())
    return failure();
  while (succeeded(parser.parseOptionalKeyword("case")))
    if (parseCase(*result.addRegion()))
      return failure();
  if (succeeded(parser.parseOptionalKeyword("default"))) {
    SmallVector<OpAsmParser::Argument> args;
    if (parser.parseArgumentList(args, OpAsmParser::Delimiter::OptionalParen,
                                 /*allowType=*/true) ||
        parser.parseRegion(*result.addRegion(), args))
      return failure();
  }
  return parser.parseRBrace();
}

// `%v : T -> (R...) attributes {...}`, the part both matches share. The
// cases are spelled by the case clauses and set as a property by the
// caller.
ParseResult parseMatchHead(OpAsmParser &parser, OperationState &result, Type &scrutineeType) {
  OpAsmParser::UnresolvedOperand scrutinee;
  SmallVector<Type> resultTypes;
  if (parser.parseOperand(scrutinee) || parser.parseColonType(scrutineeType) ||
      parser.parseArrow() ||
      parser.parseCommaSeparatedList(OpAsmParser::Delimiter::Paren,
                                     [&] { return parser.parseType(resultTypes.emplace_back()); }) ||
      parser.resolveOperand(scrutinee, scrutineeType, result.operands) ||
      parseAttrs(parser, result, {"cases"}))
    return failure();
  result.addTypes(resultTypes);
  return success();
}

// Prints a match, each case's key as `printKey` prints it.
template <typename Match>
void printMatch(Match op, OpAsmPrinter &printer, function_ref<void(unsigned)> printKey) {
  printer << ' ' << op.getScrutinee() << " : " << op.getScrutinee().getType() << " -> (";
  llvm::interleaveComma(op.getResultTypes(), printer);
  printer << ')';
  printer.printOptionalAttrDictWithKeyword(op->getAttrs(), {"cases"});
  printer << " {";
  for (unsigned i = 0, e = static_cast<unsigned>(op.getCases().size()); i < e; ++i) {
    printer.printNewline();
    printer << "case ";
    printKey(i);
    printer << ' ';
    printer.printRegion(op.getCaseRegion(i), /*printEntryBlockArgs=*/false);
  }
  if (Region *fallback = op.getDefaultRegion()) {
    printer.printNewline();
    printer << "default";
    if (fallback->getNumArguments() != 0) {
      printer << '(';
      llvm::interleaveComma(fallback->getArguments(), printer,
                            [&](BlockArgument arg) { printer.printRegionArgument(arg); });
      printer << ')';
    }
    printer << ' ';
    printer.printRegion(*fallback, /*printEntryBlockArgs=*/false);
  }
  printer.printNewline();
  printer << '}';
}

} // namespace

// `idr.match %v : T -> (R...) { case @C(%x: A) {...} ... default {...} }`
ParseResult MatchOp::parse(OpAsmParser &parser, OperationState &result) {
  Type scrutineeType;
  SmallVector<int32_t> cases;
  if (parseMatchHead(parser, result, scrutineeType) ||
      parseMatchBody(parser, result, [&](Region &region) -> ParseResult {
        IntegerAttr tag;
        SmallVector<OpAsmParser::Argument> fields;
        if (parseCtorRef(parser, scrutineeType, tag) ||
            parser.parseArgumentList(fields, OpAsmParser::Delimiter::Paren,
                                     /*allowType=*/true) ||
            parser.parseRegion(region, fields))
          return failure();
        cases.push_back(static_cast<int32_t>(tag.getInt()));
        return success();
      }))
    return failure();
  result.getOrAddProperties<Properties>().cases = parser.getBuilder().getDenseI32ArrayAttr(cases);
  return success();
}

void MatchOp::print(OpAsmPrinter &printer) {
  printMatch(*this, printer, [&](unsigned index) {
    printCtorRef(printer, *this, getScrutinee().getType(),
                 Builder(getContext()).getI32IntegerAttr(getCases()[index]));
    printer << '(';
    llvm::interleaveComma(getCaseRegion(index).getArguments(), printer,
                          [&](BlockArgument arg) { printer.printRegionArgument(arg); });
    printer << ')';
  });
}

// `idr.match_lit %n : T -> (R...) { case 0 {...} ... default {...} }`
ParseResult MatchLitOp::parse(OpAsmParser &parser, OperationState &result) {
  Type type;
  SmallVector<Attribute> cases;
  auto parseKey = [&]() -> FailureOr<Attribute> {
    if (auto integer = dyn_cast<IntegerType>(type)) {
      if (integer.getWidth() == 1) {
        if (succeeded(parser.parseOptionalKeyword("true")))
          return Attribute(IntegerAttr::get(integer, 1));
        if (succeeded(parser.parseOptionalKeyword("false")))
          return Attribute(IntegerAttr::get(integer, 0));
      }
      APInt value;
      SMLoc loc = parser.getCurrentLocation();
      if (parser.parseInteger(value))
        return failure();
      unsigned width = integer.getWidth();
      if ((value.isNegative() ? value.getSignificantBits() : value.getActiveBits()) > width)
        return parser.emitError(loc, "key does not fit in ") << type;
      return Attribute(IntegerAttr::get(
          integer, value.isNegative() ? value.sextOrTrunc(width) : value.zextOrTrunc(width)));
    }
    if (isa<StrType>(type)) {
      std::string bytes;
      if (parser.parseString(&bytes))
        return failure();
      return Attribute(parser.getBuilder().getStringAttr(bytes));
    }
    if (!isa<BigType, NatType>(type))
      return parser.emitError(parser.getCurrentLocation(), "a literal match on ")
             << type << " has no keys";
    BigAttr big;
    if (parser.parseAttribute(big))
      return failure();
    return Attribute(big);
  };
  if (parseMatchHead(parser, result, type))
    return failure();
  // A key is a literal of the value read, whatever its view's grade.
  type = unrestricted(type);
  if (parseMatchBody(parser, result, [&](Region &region) -> ParseResult {
        FailureOr<Attribute> key = parseKey();
        if (failed(key) || parser.parseRegion(region))
          return failure();
        cases.push_back(*key);
        return success();
      }))
    return failure();
  result.getOrAddProperties<Properties>().cases = parser.getBuilder().getArrayAttr(cases);
  return success();
}

void MatchLitOp::print(OpAsmPrinter &printer) {
  printMatch(*this, printer,
             [&](unsigned index) { printer.printAttributeWithoutType(getCases()[index]); });
}
