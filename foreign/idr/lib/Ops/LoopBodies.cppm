// idr.ops:loopbodies: the body of a loop over an array (idr.array.generate,
// idr.array.fold): its rule and its syntax.
export module idr.ops:loopbodies;

import idr.mlir;
import idr.dialect;

using namespace mlir;
using namespace idr;

export namespace idr::ops {

// The body of a loop over an array ends in idr.yield, or in ub.unreachable
// after a crash.
LogicalResult verifyLoopEnd(Operation *op, Region &body) {
  if (isa<YieldOp, ub::UnreachableOp>(body.front().getTerminator()))
    return success();
  return op->emitOpError("expects its body to end in idr.yield or ub.unreachable");
}

// `(%x: T, ...)` and the region they are the arguments of.
ParseResult parseLoopBody(OpAsmParser &parser, OperationState &result) {
  SmallVector<OpAsmParser::Argument> args;
  if (parser.parseArgumentList(args, OpAsmParser::Delimiter::Paren, /*allowType=*/true))
    return failure();
  return parser.parseRegion(*result.addRegion(), args);
}

void printLoopBody(OpAsmPrinter &printer, Region &body) {
  printer << " (";
  llvm::interleaveComma(body.getArguments(), printer,
                        [&](BlockArgument arg) { printer.printRegionArgument(arg); });
  printer << ") ";
  printer.printRegion(body, /*printEntryBlockArgs=*/false);
}

} // namespace idr::ops
