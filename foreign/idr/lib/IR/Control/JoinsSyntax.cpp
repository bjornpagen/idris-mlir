// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The syntax of idr.join and idr.loop, one template per direction,
// instantiated per member: a region's tokens are written once, at the head
// of the region that begins with them, so a member's text says where its
// tokens are as its constant does.

#include "idr/IR/Control/Family.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/OpImplementation.h"

using namespace mlir;
using namespace idr;

namespace {

// `(%k0, %k1)`, a region's tokens, given the token type.
ParseResult parseTokens(OpAsmParser &parser, SmallVectorImpl<OpAsmParser::Argument> &args) {
  Type token = parser.getBuilder().getType<TokenType>();
  return parser.parseCommaSeparatedList(OpAsmParser::Delimiter::Paren, [&] {
    if (parser.parseArgument(args.emplace_back()))
      return failure();
    args.back().type = token;
    return success();
  });
}

void printValues(OpAsmPrinter &printer, ValueRange values) {
  printer << '(';
  llvm::interleaveComma(values, printer, [&](Value value) { printer.printOperand(value); });
  printer << ')';
}

// `idr.join tokens(%k0, ...) in (%l, ... : !L, ...) -> (T, ...) attr-dict {body}
// join(%p: A, ...) {region} ...`, `in (...)` the lifetimes it states, one
// per scoped value it makes, absent where it makes none; an idr.loop's
// join regions also print their own tokens:
// `join tokens(%a0, ...)(%p: A, ...) {region}`. The erased binders are a
// property, printed in the attribute dictionary.
template <JoinFamily Group>
ParseResult parseGroup(OpAsmParser &parser, OperationState &state) {
  SmallVector<OpAsmParser::Argument> body;
  SmallVector<Type> results;
  if (parser.parseKeyword("tokens") || parseTokens(parser, body))
    return failure();
  if (succeeded(parser.parseOptionalKeyword("in"))) {
    SmallVector<OpAsmParser::UnresolvedOperand> outers;
    SmallVector<Type> lifetimes;
    if (parser.parseLParen() || parser.parseOperandList(outers) ||
        parser.parseColonTypeList(lifetimes) || parser.parseRParen() ||
        parser.resolveOperands(outers, lifetimes, parser.getCurrentLocation(), state.operands))
      return failure();
  }
  if (parser.parseArrow() || parser.parseLParen())
    return failure();
  if (failed(parser.parseOptionalRParen())) {
    if (parser.parseTypeList(results) || parser.parseRParen())
      return failure();
  }
  state.addTypes(results);
  if (parser.parseOptionalAttrDictWithKeyword(state.attributes) ||
      parser.parseRegion(*state.addRegion(), body))
    return failure();
  while (succeeded(parser.parseOptionalKeyword("join"))) {
    SmallVector<OpAsmParser::Argument> args;
    if constexpr (tokensAt<Group> == TokenScope::InEveryRegion) {
      if (parser.parseKeyword("tokens") || parseTokens(parser, args))
        return failure();
    }
    if (parser.parseArgumentList(args, OpAsmParser::Delimiter::Paren, /*allowType=*/true) ||
        parser.parseRegion(*state.addRegion(), args))
      return failure();
  }
  return success();
}

template <JoinFamily Group>
void printGroup(Group op, OpAsmPrinter &printer) {
  printer << " tokens";
  printValues(printer, op.getTokens(op.getBody()));
  if (!op.getOuters().empty()) {
    printer << " in (";
    printer.printOperands(op.getOuters());
    printer << " : ";
    llvm::interleaveComma(op.getOuters().getTypes(), printer);
    printer << ')';
  }
  printer << " -> (";
  llvm::interleaveComma(op->getResultTypes(), printer);
  printer << ')';
  printer.printOptionalAttrDictWithKeyword(op->getAttrs());
  printer << ' ';
  printer.printRegion(op.getBody(), /*printEntryBlockArgs=*/false);
  for (Region &region : op.getJoinRegions()) {
    printer << " join";
    if constexpr (tokensAt<Group> == TokenScope::InEveryRegion) {
      printer << " tokens";
      printValues(printer, op.getTokens(region));
    }
    printer << '(';
    llvm::interleaveComma(op.getParameters(region), printer,
                          [&](BlockArgument arg) { printer.printRegionArgument(arg); });
    printer << ") ";
    printer.printRegion(region, /*printEntryBlockArgs=*/false);
  }
}

} // namespace

ParseResult JoinOp::parse(OpAsmParser &parser, OperationState &state) {
  return parseGroup<JoinOp>(parser, state);
}

void JoinOp::print(OpAsmPrinter &printer) { printGroup(*this, printer); }

ParseResult LoopOp::parse(OpAsmParser &parser, OperationState &state) {
  return parseGroup<LoopOp>(parser, state);
}

void LoopOp::print(OpAsmPrinter &printer) { printGroup(*this, printer); }
