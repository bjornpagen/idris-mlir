// idr.graph:intailpositionmoduloconstructor: tail position modulo a
// constructor, where what a self call computes is a field of the
// constructor the function returns.
export module idr.graph:intailpositionmoduloconstructor;

import idr.mlir;
import idr.dialect;

import :intailposition;
import :isselfcall;
import :moduloat;

using namespace mlir;

export namespace idr::graph {

// Whether `call` is the self call of a tail modulo constructor, in a block
// in tail position: idr-trmc writes its result into the constructor the
// block returns, which it builds before the call.
bool inTailPositionModuloConstructor(func::CallOp call) {
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

} // namespace idr::graph
