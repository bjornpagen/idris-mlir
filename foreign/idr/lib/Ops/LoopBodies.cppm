// idr.ops:loopbodies: the body of a loop over an array (idr.array.generate,
// idr.array.fold): its rule and its syntax.
export module idr.ops:loopbodies;

import idr.mlir;
import idr.dialect;

using namespace mlir;
using namespace idr;

export namespace idr::ops {

// The body of a loop over an array: one block whose arguments are `args`,
// ending in an idr.yield of one value of `yields` (at any grade) or in
// ub.unreachable after a crash.
LogicalResult verifyLoopBody(Operation *op, Region &body, TypeRange args, Type yields) {
  Block &block = body.front();
  if (block.getArgumentTypes() != args)
    return op->emitOpError("expects its body to take ")
           << args << ", not " << block.getArgumentTypes();
  Operation *terminator = block.getTerminator();
  if (isa<ub::UnreachableOp>(terminator))
    return success();
  auto yield = dyn_cast<YieldOp>(terminator);
  if (!yield)
    return op->emitOpError("expects its body to end in idr.yield or ub.unreachable");
  if (yield.getNumOperands() != 1 || unrestricted(yield.getOperand(0).getType()) != yields)
    return yield.emitOpError("yields ")
           << yield.getOperandTypes() << ", but the loop's body gives " << yields;
  return success();
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
