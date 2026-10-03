// idr.ops:matchsyntax: the syntax idr.match and idr.match_lit share: a
// head, then a case per key and a default.
export module idr.ops:matchsyntax;

import idr.mlir;
import idr.dialect;

using namespace mlir;
using namespace idr;

export namespace idr::ops {

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

// `%v : T -> (R...) attributes {...}`, the part both matches share.
ParseResult parseMatchHead(OpAsmParser &parser, OperationState &result, Type &scrutineeType) {
  OpAsmParser::UnresolvedOperand scrutinee;
  SmallVector<Type> resultTypes;
  if (parser.parseOperand(scrutinee) || parser.parseColonType(scrutineeType) ||
      parser.parseArrow() ||
      parser.parseCommaSeparatedList(OpAsmParser::Delimiter::Paren,
                                     [&] { return parser.parseType(resultTypes.emplace_back()); }) ||
      parser.resolveOperand(scrutinee, scrutineeType, result.operands) ||
      parser.parseOptionalAttrDictWithKeyword(result.attributes))
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

} // namespace idr::ops
