// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The untyped half of the one query API: an `Operation *`'s effects, read
// through one interface dispatch. An op of ours answers with its
// declaration (DeclaredEffectsOpInterface); an op of another dialect with
// its MLIR effect instances, folded into a set once per query, which is
// where the effect system meets MLIR's open set of ops and resources.

#include "idr/IR/Effects/Query.h"

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Visitors.h"

using namespace mlir;

namespace idr::effects {

namespace {

// Which of upstream's four kinds an effect is. A kind of another dialect's,
// which MLIR's open set of effects allows, is taken as a write: it keeps
// the op and orders it with everything it may touch.
Kind kindOf(const MemoryEffects::Effect *instance) {
  return [&]<std::size_t... I>(std::index_sequence<I...>) {
    Kind found = Kind::Write;
    ((instance->getEffectID() == EffectOf<static_cast<Kind>(I)>::type::getEffectID()
          ? (found = static_cast<Kind>(I), true)
          : false) ||
     ...);
    return found;
  }(std::make_index_sequence<EnumTraits<Kind>::count>{});
}

// Which state an effect of MLIR's names: the one dynamic fact of the tree,
// forced by MLIR's open set of resources, a compare of the resource's class
// with each state's. A resource that is none of ours nor upstream's root or
// frame (another dialect's) is the root: it may be anything.
ResourceId stateOf(const SideEffects::Resource *named) {
  return [&]<std::size_t... I>(std::index_sequence<I...>) {
    ResourceId found = ResourceId::Root;
    ((named->getResourceID() == ClassOf<static_cast<ResourceId>(I)>::type::getResourceID()
          ? (found = static_cast<ResourceId>(I), true)
          : false) ||
     ...);
    return found;
  }(std::make_index_sequence<EnumTraits<ResourceId>::count>{});
}

bool recursive(Operation *op) { return op->hasTrait<OpTrait::HasRecursiveMemoryEffects>(); }

// The instances an op of another dialect declares, folded into a set. An
// allocation the set keeps is of the op's own results; any other is a write
// of its state, which keeps the op and orders it.
EffectSet fold(Operation *op, MemoryEffectOpInterface memory) {
  SmallVector<MemoryEffects::EffectInstance> instances;
  memory.getEffects(instances);
  EffectSet set;
  for (const MemoryEffects::EffectInstance &instance : instances) {
    Effect each = effectOf(instance);
    Kind kind = each.kind == Kind::Allocate && !detail::ownResult(op, each.value) ? Kind::Write : each.kind;
    set.add(kind, each.resource);
  }
  return set;
}

// Each instance of an op's own effects, visited until `visit` stops.
detail::Walked eachInstance(MemoryEffectOpInterface memory,
                            function_ref<detail::Walked(const MemoryEffects::EffectInstance &)> visit) {
  SmallVector<MemoryEffects::EffectInstance> instances;
  memory.getEffects(instances);
  for (const MemoryEffects::EffectInstance &instance : instances)
    if (visit(instance) == detail::Walked::Stopped)
      return detail::Walked::Stopped;
  return detail::Walked::All;
}

} // namespace

Effect effectOf(const MemoryEffects::EffectInstance &instance) {
  Kind kind = kindOf(instance.getEffect());
  ResourceId state = stateOf(instance.getResource());
  Value value = instance.getValue();
  if (state == ResourceId::Root && value)
    state = valueMemory[kind];
  return {kind, state, value};
}

Row reportedBy(Operation *op) { return runtimeMemoryAtoms[own(op).memory]; }

EffectSet own(Operation *op) {
  if (auto declared = dyn_cast<DeclaredEffectsOpInterface>(op))
    return declared.getDeclaredEffects();
  if (auto memory = dyn_cast<MemoryEffectOpInterface>(op))
    return fold(op, memory);
  if (recursive(op))
    return {};
  return EffectSet::everything();
}

EffectSet whole(Operation *op) {
  EffectSet set;
  op->walk<WalkOrder::PreOrder>([&](Operation *nested) {
    set = set | own(nested);
    return recursive(nested) ? WalkResult::advance() : WalkResult::skip();
  });
  return set;
}

namespace detail {

bool ownResult(Operation *op, Value value) {
  auto result = dyn_cast_if_present<OpResult>(value);
  return result && result.getOwner() == op;
}

Walked eachEffect(Operation *op, function_ref<Walked(Operation *, const Effect &)> visit) {
  Walked walked = Walked::All;
  op->walk<WalkOrder::PreOrder>([&](Operation *nested) {
    auto memory = dyn_cast<MemoryEffectOpInterface>(nested);
    if (!memory && !recursive(nested)) {
      walked = Walked::Stopped;
      return WalkResult::interrupt();
    }
    if (memory &&
        eachInstance(memory, [&](const MemoryEffects::EffectInstance &instance) {
          return visit(nested, effectOf(instance));
        }) == Walked::Stopped) {
      walked = Walked::Stopped;
      return WalkResult::interrupt();
    }
    return recursive(nested) ? WalkResult::advance() : WalkResult::skip();
  });
  return walked;
}

} // namespace detail

namespace {

// Whether some instance of `op`'s own effects is of one of the kinds, on one
// of the states, naming what `names` asks for.
bool declares(Operation *op, Kinds kinds, Resources states,
              function_ref<bool(const MemoryEffects::EffectInstance &)> names) {
  auto memory = dyn_cast<MemoryEffectOpInterface>(op);
  if (!memory)
    return false;
  bool found = false;
  eachInstance(memory, [&](const MemoryEffects::EffectInstance &instance) {
    Effect each = effectOf(instance);
    found = kinds.contains(each.kind) && states.contains(each.resource) && names(instance);
    return found ? detail::Walked::Stopped : detail::Walked::All;
  });
  return found;
}

} // namespace

bool consumes(OpOperand &operand) {
  return declares(operand.getOwner(), Kinds{Kind::Free}, Resources{ResourceId::Count},
                  [&](const MemoryEffects::EffectInstance &instance) {
                    return instance.getEffectValue<OpOperand *>() == &operand;
                  });
}

bool allocates(Operation *op, Value value) {
  return declares(op, Kinds{Kind::Allocate}, Resources::top(),
                  [&](const MemoryEffects::EffectInstance &instance) { return instance.getValue() == value; });
}

bool changes(Operation *op, Value value) {
  return declares(op, Kinds{Kind::Write, Kind::Free}, Resources::top(),
                  [&](const MemoryEffects::EffectInstance &instance) { return instance.getValue() == value; });
}

} // namespace idr::effects
