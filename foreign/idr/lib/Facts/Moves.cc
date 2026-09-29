// Which code may be dropped, delayed or moved, from what its ops may do.

#include "Facts/Facts.h"

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
    auto callee = SymbolTable::lookupNearestSymbolFrom<func::FuncOp>(call, call.getCalleeAttr());
    if (!callee)
      return facts::Effects::all();
    out = facts::of(callee);
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

// Whether every op in `op`, itself included, does only what `allowed`
// accepts.
bool only(Operation *op, function_ref<bool(const facts::Effects &)> allowed) {
  return !op->walk([&](Operation *inner) {
              return allowed(own(inner)) ? WalkResult::advance() : WalkResult::interrupt();
            })
              .wasInterrupted();
}

} // namespace

bool facts::canMoveAcross(Operation *op) {
  return only(op, [](const Effects &effects) { return effects.none(); });
}

bool facts::canDelay(Operation *op) {
  return only(op, [](const Effects &effects) { return !effects.io; });
}

bool facts::canDrop(func::CallOp call) { return call->use_empty() && canMoveAcross(call); }
