// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What an op, or everything in its regions, may do, without the values it
// names: per kind, the states it acts on, and whether its runtime function
// holds memory no value names. Every question about effects that is not
// about one value is a question about this set, answered against the tree:
// two effects conflict only when one's state is the other's or above it, so
// a crash and a heap write never conflict, and "does IO" is an effect on
// the outside itself or on a state above it, never one on a crash beneath
// it. States are compared exactly, by the tree's own order, never by
// upstream's `isa` on a resource, which holds of every descendant.
#ifndef IDR_IR_EFFECTS_SET_H
#define IDR_IR_EFFECTS_SET_H

#include "idr/IR/Effects/Vocabulary.h"

namespace idr::effects {

struct EffectSet {
  // Per kind, the states an effect of that kind is on. An allocation is
  // always of the op's own results: an op of ours can declare no other, and
  // the fold of another dialect's effects keeps no other as one.
  EnumArray<Kind, Resources> byKind{};
  RuntimeMemory memory = RuntimeMemory::Untouched;

  // What an op that declares nothing may do: anything, on the root, which
  // every state is beneath.
  static constexpr EffectSet everything() {
    EffectSet all;
    for (Kind kind : allOf<Kind>())
      all.byKind[kind] = Resources{ResourceId::Root};
    all.memory = RuntimeMemory::Touched;
    return all;
  }

  constexpr EffectSet &add(Kind kind, ResourceId state) {
    byKind[kind] = byKind[kind] | Resources{state};
    return *this;
  }

  friend constexpr EffectSet operator|(EffectSet a, const EffectSet &b) {
    for (Kind kind : allOf<Kind>())
      a.byKind[kind] = a.byKind[kind] | b.byKind[kind];
    if (b.memory == RuntimeMemory::Touched)
      a.memory = RuntimeMemory::Touched;
    return a;
  }

  friend constexpr bool operator==(const EffectSet &, const EffectSet &) = default;

  // Whether an effect of the kind is declared on exactly this state.
  constexpr bool on(Kind kind, ResourceId state) const { return byKind[kind].contains(state); }

  // Whether an effect of the kind may act on the state: one on it, or on a
  // state above it, which holds it.
  constexpr bool mayAct(Kind kind, ResourceId state) const {
    return !(byKind[kind] & atOrAbove[state]).empty();
  }

  // Whether some effect acts on the state or on a part of it: what is
  // ordered with output is within the outside, a crash and an exit among
  // it.
  constexpr bool within(ResourceId state) const {
    for (Kind kind : allOf<Kind>())
      if (!(byKind[kind] & atOrBelow[state]).empty())
        return true;
    return false;
  }

  // Whether the two may not be reordered: a write or a release in one on a
  // state the other reads, writes or releases, or on one above or below it.
  // An allocation names a fresh value nothing else reaches, so it conflicts
  // with nothing.
  constexpr bool conflicts(const EffectSet &other) const {
    return changes().hits(other.touched()) || other.changes().hits(touched());
  }

  // Whether the op may be deleted when its results are unused: it writes and
  // gives back nothing. A crash and a divergence are writes, so a call whose
  // row holds either stays.
  constexpr bool deadIfUnused() const {
    return byKind[Kind::Write].empty() && byKind[Kind::Free].empty();
  }

  // Whether the op only computes its results: at most it makes fresh ones.
  // It may move across any op, run on fewer paths, or not at all.
  constexpr bool onlyComputes() const {
    return byKind[Kind::Read].empty() && deadIfUnused();
  }

  // What the set summarizes as in a function's row.
  constexpr Row row() const {
    Row atoms = runtimeMemoryAtoms[memory];
    for (Kind kind : allOf<Kind>())
      for (ResourceId state : allOf<ResourceId>())
        if (byKind[kind].contains(state))
          atoms = atoms | project(kind, state);
    return atoms;
  }

private:
  // The states its effects reach, with every state above and below each.
  struct Reach {
    Resources states;
    constexpr bool hits(const Reach &other) const {
      Resources related;
      for (ResourceId state : allOf<ResourceId>())
        if (other.states.contains(state))
          related = related | atOrAbove[state] | atOrBelow[state];
      return !(states & related).empty();
    }
  };
  constexpr Reach changes() const { return {byKind[Kind::Write] | byKind[Kind::Free]}; }
  constexpr Reach touched() const {
    return {byKind[Kind::Read] | byKind[Kind::Write] | byKind[Kind::Free]};
  }
};

} // namespace idr::effects

#endif // IDR_IR_EFFECTS_SET_H
