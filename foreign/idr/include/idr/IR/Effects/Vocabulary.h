// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The effect system's words in C++, as the dialect's specification states
// them (IdrisMLIR.Spec.Effects): the states of the tree and the classes
// MLIR's effects name them by, the kinds, the atoms of a row, the typed
// rules, and the form of an op's declaration the generated Effects.h.inc
// writes for every op (Declared<Op>). Every fact here is a load from a
// table printed from the specification (Generated/EffectTree.h.inc); this
// header states none of its own.
#ifndef IDR_IR_EFFECTS_VOCABULARY_H
#define IDR_IR_EFFECTS_VOCABULARY_H

#include "idr/Support/Enum.h"

#include "mlir/IR/Operation.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"

#include <array>
#include <cstddef>
#include <cstdint>
#include <string_view>
#include <tuple>
#include <utility>

// The closed sets of the effect system and their tables, in ::idr.
#include "idr/IR/Generated/EffectTree.h.inc"

namespace idr::effects {

using ResourceId = ::idr::ResourceId;
using Kind = ::idr::EffectKind;
using Atom = ::idr::Atom;
using Condition = ::idr::EffectCondition;
using Landing = ::idr::EffectLanding;
using Rule = ::idr::EffectRule;
using RuntimeMemory = ::idr::RuntimeMemory;

// A set of states, of kinds, of atoms. A function's row is a set of atoms.
using Resources = EnumSet<ResourceId>;
using Kinds = EnumSet<Kind>;
using Row = EnumSet<Atom>;

// The effect instances MLIR's interface gathers.
using Instances = llvm::SmallVectorImpl<mlir::SideEffects::EffectInstance<mlir::MemoryEffects::Effect>>;

//===----------------------------------------------------------------------===//
// The states, as MLIR's resources
//===----------------------------------------------------------------------===//

template <ResourceId R>
class State;

// The class MLIR's effects name a state by: upstream's own for its root and
// frame, the one class template below for each of ours.
template <ResourceId R>
struct ClassOf {
  using type = State<R>;
};
template <>
struct ClassOf<ResourceId::Root> {
  using type = mlir::SideEffects::DefaultResource;
};
template <>
struct ClassOf<ResourceId::Frame> {
  using type = mlir::SideEffects::AutomaticAllocationScopeResource;
};

// A state of ours, everything about it read from the tree's tables: its
// printed name, its parent (which is how upstream orders it with every
// other state), and whether an effect on it may name a value, which upstream
// checks against every value effect.
template <ResourceId R>
class State : public mlir::SideEffects::Resource::Base<State<R>> {
public:
  llvm::StringRef getName() const final { return resourcePrinted[R]; }
  mlir::SideEffects::Resource *getParent() const final {
    return ClassOf<resourceParent[R]>::type::get();
  }
  bool isAddressable() const final { return resourceReach[R] == ResourceReach::Addressable; }
};

} // namespace idr::effects

// Each state of ours by its name, `::idr::effects::Heap` and kin, the names
// ODS's effect decorators use: `State<ResourceId::Heap>`, printed from the
// specification's list of the tree's states.
#include "idr/IR/Generated/Resources.h.inc"

namespace idr::effects {

// The resource instance of a state.
template <ResourceId R>
mlir::SideEffects::Resource *resource() {
  return ClassOf<R>::type::get();
}

// The resource instance of a state known only at run time: one load from a
// table of the instances' getters, built when the compiler is built.
inline mlir::SideEffects::Resource *resource(ResourceId state) {
  static constexpr auto getters = []<std::size_t... I>(std::index_sequence<I...>) {
    return std::array<mlir::SideEffects::Resource *(*)(), sizeof...(I)>{
        &resource<static_cast<ResourceId>(I)>...};
  }(std::make_index_sequence<EnumTraits<ResourceId>::count>{});
  return getters[std::to_underlying(state)]();
}

// Upstream's effect class of each kind, its four and no other.
template <Kind K>
struct EffectOf;
template <>
struct EffectOf<Kind::Read> {
  using type = mlir::MemoryEffects::Read;
};
template <>
struct EffectOf<Kind::Write> {
  using type = mlir::MemoryEffects::Write;
};
template <>
struct EffectOf<Kind::Allocate> {
  using type = mlir::MemoryEffects::Allocate;
};
template <>
struct EffectOf<Kind::Free> {
  using type = mlir::MemoryEffects::Free;
};

template <Kind K>
mlir::MemoryEffects::Effect *effect() {
  return EffectOf<K>::type::get();
}

// The effect instance of a kind known only at run time.
inline mlir::MemoryEffects::Effect *effect(Kind kind) {
  static constexpr auto getters = []<std::size_t... I>(std::index_sequence<I...>) {
    return std::array<mlir::MemoryEffects::Effect *(*)(), sizeof...(I)>{
        &effect<static_cast<Kind>(I)>...};
  }(std::make_index_sequence<EnumTraits<Kind>::count>{});
  return getters[std::to_underlying(kind)]();
}

//===----------------------------------------------------------------------===//
// The tree's order, computed when the compiler is built
//===----------------------------------------------------------------------===//

// Every state at or above each state, up to the root, which is its own
// parent: the walk ends there, and the specification's tree, every parent
// declared before its child, is why it ends.
inline constexpr EnumArray<ResourceId, Resources> atOrAbove = [] {
  EnumArray<ResourceId, Resources> up{};
  for (ResourceId start : allOf<ResourceId>()) {
    ResourceId at = start;
    up[start] = up[start] | Resources{at};
    while (resourceParent[at] != at) {
      at = resourceParent[at];
      up[start] = up[start] | Resources{at};
    }
  }
  return up;
}();

// Every state at or below each state.
inline constexpr EnumArray<ResourceId, Resources> atOrBelow = [] {
  EnumArray<ResourceId, Resources> down{};
  for (ResourceId below : allOf<ResourceId>())
    for (ResourceId above : allOf<ResourceId>())
      if (atOrAbove[below].contains(above))
        down[above] = down[above] | Resources{below};
  return down;
}();

// What an effect of the kind on the state summarizes as in a row, naming no
// value. An effect of another dialect on memory through a value is folded
// onto `valueMemory` before it is projected.
constexpr Row project(Kind kind, ResourceId state) {
  switch (kind) {
  case Kind::Read:
    return projectRead[state];
  case Kind::Write:
    return projectWrite[state];
  case Kind::Allocate:
    return projectAllocate[state];
  case Kind::Free:
    return projectFree[state];
  }
  std::unreachable();
}

// The atoms after which a run may not return to its caller: what LLVM is
// not told `willreturn` of, and what keeps a call from running where it
// would not have.
inline constexpr Row mayNotReturn = [] {
  Row atoms;
  for (Atom atom : allOf<Atom>())
    if (atomWithholds[atom].contains(FunctionAttribute::WillReturn))
      atoms = atoms | Row{atom};
  return atoms;
}();

//===----------------------------------------------------------------------===//
// An op's declaration, as Generated/Effects.h.inc writes it
//===----------------------------------------------------------------------===//

// Whether an op declares its effects, or, as a definition never executed
// where it stands, declares nothing to MLIR.
enum class Form : std::uint8_t { Everything, Declares };

// Whether an op's regions add their effects to its own.
enum class Bodies : std::uint8_t { Own, WithRegions };

// What an effect is on: the op as a whole, or each value of one of its
// operand or result groups, by ODS's numbering.
struct Subject {
  enum class Of : std::uint8_t { Op, Operand, Result };
  Of of;
  unsigned group;

  static constexpr Subject op() { return {Of::Op, 0}; }
  static constexpr Subject operand(unsigned group) { return {Of::Operand, group}; }
  static constexpr Subject result(unsigned group) { return {Of::Result, group}; }
};

// One static effect of an op.
struct Static {
  Kind kind;
  ResourceId resource;
  Subject subject;
};

// The group a typed rule reads, as a type, so its expansion is the op's.
struct OnOp {};
template <unsigned Group>
struct OnOperand {};
template <unsigned Group>
struct OnResult {};

// A typed rule: the effects that follow from the type of each value of the
// group it reads, from the rule's row of the specification's table.
template <Rule R, class Where>
struct ByType {};

template <class Where>
using Consumes = ByType<Rule::Consumes, Where>;
template <class Where>
using NewIdentity = ByType<Rule::NewIdentity, Where>;
template <class Where>
using Acquires = ByType<Rule::Acquires, Where>;
template <class Where>
using ReadsMemo = ByType<Rule::ReadsMemo, Where>;
template <class Where>
using CountsIfShared = ByType<Rule::CountsIfShared, Where>;
template <class Where>
using Recycles = ByType<Rule::Recycles, Where>;
template <class Where>
using ReleasesForeign = ByType<Rule::ReleasesForeign, Where>;
template <class Where>
using ReadsBuffers = ByType<Rule::ReadsBuffers, Where>;
template <class Where>
using WritesBuffers = ByType<Rule::WritesBuffers, Where>;

// A call's effects: each ordering atom of the row it carries, and a write
// on each operand its callee writes through. Not a rule over a type: the
// row is the call's, which its callee's derivation writes.
template <class Where>
struct Summarized {};

// Memory the op's runtime function holds that no value names: no MLIR
// effect, and `alloc` and `free` in a row.
template <class Where>
struct HoldsRuntimeMemory {};

// Each op's declaration, specialized for every op of the dialect by the
// generated Effects.h.inc: its form; and, for an op that declares, its
// static effects, its typed rules and whether its regions' count.
template <class OpT>
struct Declared;

// A condition of a typed rule, read off one value's type: one predicate
// each, defined in lib/IR/Effects/Conditions.cpp and declared here so every
// unit that expands a rule calls that one. A condition with no predicate
// does not link.
template <Condition C>
bool holds(mlir::Type type);
template <>
bool holds<Condition::OwnsCount>(mlir::Type type);
template <>
bool holds<Condition::HasIdentity>(mlir::Type type);
template <>
bool holds<Condition::MemoCell>(mlir::Type type);
template <>
bool holds<Condition::MayBeShared>(mlir::Type type);
template <>
bool holds<Condition::HoldsItsCell>(mlir::Type type);
template <>
bool holds<Condition::ReachesForeign>(mlir::Type type);
template <>
bool holds<Condition::Buffer>(mlir::Type type);

} // namespace idr::effects

#endif // IDR_IR_EFFECTS_VOCABULARY_H
