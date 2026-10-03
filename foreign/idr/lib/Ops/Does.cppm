// idr.ops:does: what one op does, which decides whether it may move, run on
// fewer paths, or not at all (idr::onlyAllocates, idr::performsIO).
export module idr.ops:does;

import idr.mlir;
import idr.dialect;

using namespace mlir;
using namespace idr;

export namespace idr::ops {

// What `op` alone does, nested ops aside: nothing, when it has no effects
// or all of them are allocations of its results; IO, when it reads the IO
// resource (a crash and a loop that may not end only write it, which
// orders them after output without making them output); otherwise
// something. An op whose effects MLIR does not know may do anything.
enum class Does { Nothing, IO, Something };

Does does(Operation *op) {
  if (op->hasTrait<OpTrait::HasRecursiveMemoryEffects>() || isa<ub::UnreachableOp>(op))
    return Does::Nothing;
  auto iface = dyn_cast<MemoryEffectOpInterface>(op);
  if (!iface)
    return Does::Something;
  SmallVector<MemoryEffects::EffectInstance> effects;
  iface.getEffects(effects);
  Does out = Does::Nothing;
  for (const MemoryEffects::EffectInstance &effect : effects) {
    if (effect.getResource() == IOResource::get() && isa<MemoryEffects::Read>(effect.getEffect()))
      return Does::IO;
    if (!isa<MemoryEffects::Allocate>(effect.getEffect()) ||
        !isa_and_present<OpResult>(effect.getValue()))
      out = Does::Something;
  }
  return out;
}

} // namespace idr::ops
