// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What an op, or everything in its regions, may do, without the values it
// names: per kind, the states it acts on, and what it reports in a row that
// orders nothing (memory acquired or given back that no value names). Every
// question about effects that is not about one value is a question about
// this set, answered against the tree: two effects conflict only when one's
// state is the other's or above it, so a crash and a heap write never
// conflict, and "does IO" is an effect on the outside itself or on a state
// above it, never one on a crash beneath it. States are compared exactly,
// by the tree's own order, never by upstream's `isa` on a resource, which
// holds of every descendant.
#ifndef IDR_IR_EFFECTS_SET_H
#define IDR_IR_EFFECTS_SET_H

#include "idr/IR/Effects/Vocabulary.h"

namespace idr::effects {

struct EffectSet {
  // Per kind, the states an effect of that kind is on. An allocation is
  // always of the op's own results: an op of ours can declare no other, and
  // the fold of another dialect's effects keeps no other as one.
  EnumArray<Kind, Resources> byKind{};
  // What it reports in its function's row beyond its effects on states:
  // memory its runtime function, or a call's callee, acquires or gives back
  // that no value of the program names. Nothing is ordered with it, so only
  // `row` reads it.
  Row reported;

  // What an op that declares nothing may do: anything, on the root, which
  // every state is beneath, and hold any memory.
  static constexpr EffectSet everything() {
    EffectSet all;
    for (Kind kind : allOf<Kind>())
      all.byKind[kind] = Resources{ResourceId::Root};
    all.reported = runtimeMemoryAtoms[RuntimeMemory::Touched];
    return all;
  }

  constexpr EffectSet &add(Kind kind, ResourceId state) {
    byKind[kind] = byKind[kind] | Resources{state};
    return *this;
  }

  friend constexpr EffectSet operator|(EffectSet a, const EffectSet &b) {
    for (Kind kind : allOf<Kind>())
      a.byKind[kind] = a.byKind[kind] | b.byKind[kind];
    a.reported = a.reported | b.reported;
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

  // Whether the two may not be reordered: a write or a release in one on a
  // state the other reads, writes or releases, or on one above or below it.
  // An allocation names a fresh value nothing else reaches, so it conflicts
  // with nothing.
  constexpr bool conflicts(const EffectSet &other) const {
    return changes().hits(other.touched()) || other.changes().hits(touched());
  }

  // Whether the op only computes its results: at most it makes fresh ones.
  // It may move across any op, run on fewer paths, or not at all. A crash
  // and a divergence are writes, so an op that may do either does more.
  constexpr bool onlyComputes() const {
    return byKind[Kind::Read].empty() && byKind[Kind::Write].empty() && byKind[Kind::Free].empty();
  }

  // What the set summarizes as in a function's row.
  constexpr Row row() const {
    Row atoms = reported;
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

namespace idr {

// The default of DeclaredEffectsOpInterface's method, an op's own effects
// read off its class's declaration (Declared.h defines it). Declared here,
// before the generated interface, whose default names it by its qualified
// name and so binds to what is declared where the interface is. A
// template, so the default keeps the class it is instantiated for.
template <class OpT>
effects::EffectSet declaredEffects(OpT op);

} // namespace idr

#endif // IDR_IR_EFFECTS_SET_H
