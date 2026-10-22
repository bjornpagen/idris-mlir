// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The untyped half of the one query API: an `Operation *`'s effects, read
// through one interface dispatch. An op of ours answers with its
// declaration (DeclaredEffectsOpInterface); an op of another dialect with
// its MLIR effect instances, folded into a set once per query, which is
// where the effect system meets MLIR's open set of ops and resources. And
// MLIR's `getEffects` of every op of ours whose effects follow from types,
// generated from the specification, each the typed half's `declare`.

#include "idr/IR/Effects/Classify.h"
#include "idr/IR/Effects/Consumption.h"
#include "idr/IR/Effects/Declared.h"
#include "idr/IR/Effects/Whole.h"

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Visitors.h"
#include "llvm/ADT/STLExtras.h"

#include <array>
#include <cstddef>
#include <utility>

using namespace mlir;

namespace idr::effects {

namespace {

// Each case's upstream class, by the case's number, as the function that
// names the class: each case's class is fixed when the compiler is built,
// but a TypeID is an address fixed only when the program loads.
template <class Enum>
using ClassNames = std::array<TypeID (*)(), EnumTraits<Enum>::count>;

// The case whose class `id` names, or `otherwise`: a compare of the class
// with each case's, the one dynamic step, forced by MLIR's open sets of
// effects and resources.
template <class Enum>
Enum caseNamed(const ClassNames<Enum> &names, TypeID id, Enum otherwise) {
  for (std::size_t at = 0; at < names.size(); ++at)
    if (names[at]() == id)
      return static_cast<Enum>(at);
  return otherwise;
}

// Which of upstream's four kinds an effect is. A kind of another dialect's,
// which MLIR's open set of effects allows, is taken as a write: it keeps
// the op and orders it with everything it may touch.
Kind kindOf(const MemoryEffects::Effect *instance) {
  static constexpr auto names = []<std::size_t... I>(std::index_sequence<I...>) {
    return ClassNames<Kind>{&EffectOf<static_cast<Kind>(I)>::type::getEffectID...};
  }(std::make_index_sequence<EnumTraits<Kind>::count>{});
  return caseNamed(names, instance->getEffectID(), Kind::Write);
}

// Which state an effect of MLIR's names: the one dynamic fact of the tree,
// forced by MLIR's open set of resources. A resource that is none of ours
// nor upstream's root or frame (another dialect's) is the root: it may be
// anything.
ResourceId stateOf(const SideEffects::Resource *named) {
  static constexpr auto names = []<std::size_t... I>(std::index_sequence<I...>) {
    return ClassNames<ResourceId>{&ClassOf<static_cast<ResourceId>(I)>::type::getResourceID...};
  }(std::make_index_sequence<EnumTraits<ResourceId>::count>{});
  return caseNamed(names, named->getResourceID(), ResourceId::Root);
}

// Whether `value` is a result of `op`, the one value an allocation of
// `op`'s may name.
bool ownResult(Operation *op, Value value) {
  auto result = dyn_cast_if_present<OpResult>(value);
  return result && result.getOwner() == op;
}

// The instances an op of another dialect declares, folded into a set. An
// allocation the set keeps is of the op's own results; any other is a write
// of its state, which keeps the op and orders it.
EffectSet fold(Operation *op, MemoryEffectOpInterface memory) {
  SmallVector<MemoryEffects::EffectInstance> instances;
  memory.getEffects(instances);
  EffectSet set;
  for (const MemoryEffects::EffectInstance &instance : instances) {
    Effect each = effectOf(instance);
    Kind kind = each.kind == Kind::Allocate && !ownResult(op, each.value) ? Kind::Write : each.kind;
    set.add(kind, each.resource);
  }
  return set;
}

// Whether some instance of `op`'s own effects is of one of the kinds and
// names what `names` asks for.
template <std::predicate<const MemoryEffects::EffectInstance &> Names>
bool declares(Operation *op, Kinds kinds, const Names &names) {
  auto memory = dyn_cast<MemoryEffectOpInterface>(op);
  if (!memory)
    return false;
  SmallVector<MemoryEffects::EffectInstance, 4> instances;
  memory.getEffects(instances);
  return llvm::any_of(instances, [&](const MemoryEffects::EffectInstance &instance) {
    return kinds.contains(kindOf(instance.getEffect())) && names(instance);
  });
}

// Whether `op` itself acquires memory that `asked` is about. Memory is
// acquired on the heap or in a frame, as the tree reads each instance: a
// `memref.alloc`'s on the heap, a `memref.alloca`'s in its frame. An
// allocation on `identity` is a fresh name and no memory: a call declares
// one on each linear result, which may be the very memory an argument
// passed in and the callee gave back. An op that says nothing MLIR can read
// acquires nothing its function may keep to itself. Both forms of
// `acquires` ask through this one reading.
template <Question Q>
bool acquiresMemory(Operation *op, const Q &asked) {
  constexpr Resources memory{ResourceId::Heap, ResourceId::Frame};
  bool acquired = false;
  (void)eachOwnEffect(op, [&](const Effect &each) {
    acquired = each.kind == Kind::Allocate && memory.contains(each.resource) && asked(each);
    return acquired ? Walked::Stopped : Walked::All;
  });
  return acquired;
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

Row reportedBy(Operation *op) { return own(op).reported; }

EffectSet own(Operation *op) {
  if (auto declared = dyn_cast<DeclaredEffectsOpInterface>(op))
    return declared.getDeclaredEffects();
  if (auto memory = dyn_cast<MemoryEffectOpInterface>(op))
    return fold(op, memory);
  if (detail::recursive(op))
    return {};
  return EffectSet::everything();
}

EffectSet whole(Operation *op) {
  EffectSet set;
  op->walk<WalkOrder::PreOrder>([&](Operation *nested) {
    set = set | own(nested);
    return detail::recursive(nested) ? WalkResult::advance() : WalkResult::skip();
  });
  return set;
}

// A consumption is a free of the operand's count, which only an op of ours
// declares, on the operand itself.
bool consumes(OpOperand &operand) {
  return declares(operand.getOwner(), Kinds{Kind::Free}, [&](const MemoryEffects::EffectInstance &instance) {
    return stateOf(instance.getResource()) == ResourceId::Count &&
           instance.getEffectValue<OpOperand *>() == &operand;
  });
}

bool allocates(Operation *op, Value value) {
  return declares(op, Kinds{Kind::Allocate},
                  [&](const MemoryEffects::EffectInstance &instance) { return instance.getValue() == value; });
}

bool acquires(Operation *op, Value value) {
  return acquiresMemory(op, [&](const Effect &each) { return each.value == value; });
}

bool acquires(Operation *op) {
  return acquiresMemory(op, [](const Effect &) { return true; });
}

} // namespace idr::effects

// MLIR's `getEffects` of each op whose effects follow from types.
#include "idr/IR/Generated/Effects.cpp.inc"
