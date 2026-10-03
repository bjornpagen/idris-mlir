// Tail position modulo a constructor.
module idr.graph;

import idr.mlir;
import idr.dialect;

using namespace mlir;

bool idr::graph::inTailPositionModuloConstructor(func::CallOp call) {
  auto fn = call->getParentOfType<func::FuncOp>();
  if (!fn || !isSelfCall(call, fn))
    return false;
  Block &block = *call->getBlock();
  std::optional<Modulo> tail = moduloAt(block, fn);
  if (!tail || tail->call != call)
    return false;
  Operation *terminator = block.getTerminator();
  Operation *match = terminator->getParentOp();
  return isa<func::ReturnOp>(terminator) ||
         (isa<idr::MatchOp, idr::MatchLitOp>(match) && inTailPosition(match));
}
