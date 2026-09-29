// Whether every op in an op does only what a predicate accepts, from what
// each op itself may do.
module idr.facts;

import idr.mlir;

using namespace mlir;
using namespace idr;

namespace {

// What `op` itself may do, apart from the ops nested in it. An op that
// may crash has no other effect than allocating its result; an op whose
// effects MLIR does not know may do anything; ub.unreachable is only
// reached after an op that does not return, or never.
facts::Effects own(Operation *op) {
  facts::Effects out;
  if (op->hasTrait<PerformsIO>()) {
    out.io = true;
  } else if (auto call = dyn_cast<func::CallOp>(op)) {
    out = facts::of(
        SymbolTable::lookupNearestSymbolFrom<func::FuncOp>(call, call.getCalleeAttr()));
    for (Value operand : call.getOperands())
      out |= facts::passed(call, operand);
  } else if (auto mayCrash = dyn_cast<MayCrashOpInterface>(op)) {
    out.crash = mayCrash.getCrashCause().has_value();
  } else if (isa<MayLoopOp>(op)) {
    out.partial = true;
  } else if (!isa<ub::UnreachableOp>(op) &&
             !op->hasTrait<OpTrait::HasRecursiveMemoryEffects>()) {
    auto iface = dyn_cast<MemoryEffectOpInterface>(op);
    if (!iface)
      return facts::Effects::all();
    SmallVector<MemoryEffects::EffectInstance> effects;
    iface.getEffects(effects);
    if (!llvm::all_of(effects, [](const MemoryEffects::EffectInstance &effect) {
          return isa<MemoryEffects::Allocate>(effect.getEffect());
        }))
      return facts::Effects::all();
  }
  return out;
}

} // namespace

bool facts::only(Operation *op, function_ref<bool(const Effects &)> allowed) {
  return !op->walk([&](Operation *inner) {
              return allowed(own(inner)) ? WalkResult::advance() : WalkResult::interrupt();
            })
              .wasInterrupted();
}
