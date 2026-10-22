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

namespace idr {

namespace {

// `(%k0, %k1)`, a region's tokens, given the token type.
mlir::ParseResult parseTokens(mlir::OpAsmParser &parser,
                              llvm::SmallVectorImpl<mlir::OpAsmParser::Argument> &args) {
  mlir::Type token = parser.getBuilder().getType<mlir::TokenType>();
  return parser.parseCommaSeparatedList(mlir::OpAsmParser::Delimiter::Paren, [&] {
    if (parser.parseArgument(args.emplace_back()))
      return mlir::failure();
    args.back().type = token;
    return mlir::success();
  });
}

void printValues(mlir::OpAsmPrinter &printer, mlir::ValueRange values) {
  printer << '(';
  llvm::interleaveComma(values, printer, [&](mlir::Value value) { printer.printOperand(value); });
  printer << ')';
}

// `idr.join tokens(%k0, ...) in (%l, ... : !L, ...) -> (T, ...) attr-dict {body}
// join(%p: A, ...) {region} ...`, `in (...)` the lifetimes it states, one
// per scoped value it makes, absent where it makes none; an idr.loop's
// join regions also print their own tokens:
// `join tokens(%a0, ...)(%p: A, ...) {region}`. The erased binders are a
// property, printed in the attribute dictionary.
template <JoinFamily Group>
mlir::ParseResult parseGroup(mlir::OpAsmParser &parser, mlir::OperationState &state) {
  llvm::SmallVector<mlir::OpAsmParser::Argument> body;
  llvm::SmallVector<mlir::Type> results;
  if (parser.parseKeyword("tokens") || parseTokens(parser, body))
    return mlir::failure();
  if (mlir::succeeded(parser.parseOptionalKeyword("in"))) {
    llvm::SmallVector<mlir::OpAsmParser::UnresolvedOperand> outers;
    llvm::SmallVector<mlir::Type> lifetimes;
    if (parser.parseLParen() || parser.parseOperandList(outers) ||
        parser.parseColonTypeList(lifetimes) || parser.parseRParen() ||
        parser.resolveOperands(outers, lifetimes, parser.getCurrentLocation(), state.operands))
      return mlir::failure();
  }
  if (parser.parseArrow() || parser.parseLParen())
    return mlir::failure();
  if (mlir::failed(parser.parseOptionalRParen())) {
    if (parser.parseTypeList(results) || parser.parseRParen())
      return mlir::failure();
  }
  state.addTypes(results);
  if (parser.parseOptionalAttrDictWithKeyword(state.attributes) ||
      parser.parseRegion(*state.addRegion(), body))
    return mlir::failure();
  while (mlir::succeeded(parser.parseOptionalKeyword("join"))) {
    llvm::SmallVector<mlir::OpAsmParser::Argument> args;
    if constexpr (tokensAt<Group> == TokenScope::InEveryRegion) {
      if (parser.parseKeyword("tokens") || parseTokens(parser, args))
        return mlir::failure();
    }
    if (parser.parseArgumentList(args, mlir::OpAsmParser::Delimiter::Paren, /*allowType=*/true) ||
        parser.parseRegion(*state.addRegion(), args))
      return mlir::failure();
  }
  return mlir::success();
}

template <JoinFamily Group>
void printGroup(Group op, mlir::OpAsmPrinter &printer) {
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
  for (mlir::Region &region : op.getJoinRegions()) {
    printer << " join";
    if constexpr (tokensAt<Group> == TokenScope::InEveryRegion) {
      printer << " tokens";
      printValues(printer, op.getTokens(region));
    }
    printer << '(';
    llvm::interleaveComma(op.getParameters(region), printer,
                          [&](mlir::BlockArgument arg) { printer.printRegionArgument(arg); });
    printer << ") ";
    printer.printRegion(region, /*printEntryBlockArgs=*/false);
  }
}

} // namespace

mlir::ParseResult JoinOp::parse(mlir::OpAsmParser &parser, mlir::OperationState &state) {
  return parseGroup<JoinOp>(parser, state);
}

void JoinOp::print(mlir::OpAsmPrinter &printer) { printGroup(*this, printer); }

mlir::ParseResult LoopOp::parse(mlir::OpAsmParser &parser, mlir::OperationState &state) {
  return parseGroup<LoopOp>(parser, state);
}

void LoopOp::print(mlir::OpAsmPrinter &printer) { printGroup(*this, printer); }

} // namespace idr
