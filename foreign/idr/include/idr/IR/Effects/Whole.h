// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// An op's effects as a set, the untyped half of the one query API: an
// `Operation *` makes one interface dispatch, ours (an op's own effects as
// one set) or, for an op of another dialect, upstream's, whose instances
// are folded once into a set. Every question about an op's effects that
// names no value asks here: what it does, alone or with everything in its
// regions, what it adds to its function's row, whether memory may be taken
// while it runs, and whether two ops may trade places.
#ifndef IDR_IR_EFFECTS_WHOLE_H
#define IDR_IR_EFFECTS_WHOLE_H

#include "idr/IR/Effects/Set.h"

#include "mlir/IR/Operation.h"

namespace idr::effects {

// An op's own effects, not its regions': through our interface for an op
// of ours, through upstream's for an op of another dialect, its instances
// folded into a set; an op with neither may do anything, unless its effects
// are its regions' alone.
EffectSet own(mlir::Operation *op);

// An op's effects with everything in each region whose effects are its op's
// (MLIR's recursive memory effects), folded in one walk.
EffectSet whole(mlir::Operation *op);

// What `op`, with everything in it, adds to its function's row: its
// effects summarized, a call's row whole among them. Where in memory an
// effect lands, which the function's own derivation refines, is not read.
inline Row rowOf(mlir::Operation *op) { return whole(op).row(); }

namespace detail {

// Per kind, the states an effect on which summarizes as `alloc` in a row,
// read off the projection when the compiler is built, so asking whether
// memory may be taken tests a few bits and projects no set.
inline constexpr EnumArray<Kind, Resources> takesMemoryOn = [] {
  EnumArray<Kind, Resources> on{};
  for (Kind kind : allOf<Kind>())
    for (ResourceId state : allOf<ResourceId>())
      if (project(kind, state).contains(Atom::alloc))
        on[kind] = on[kind] | Resources{state};
  return on;
}();

} // namespace detail

// Whether memory may be taken while what `set` holds runs: whatever its row
// reports as `alloc`, so a heap cell it allocates, memory its runtime
// function holds that no value names, and what a call's callee acquires,
// which the call's row carries. Wider than `acquires`, which reads only an
// op's own allocations and so never a callee's or the runtime's, and reads
// an op that declares nothing as acquiring nothing, where this reads it as
// acquiring anything. Narrower in one place: a frame cell, which `acquires`
// counts, is its function's own and no row reports it. Asked of `own(op)`
// by a walk that meets the ops in each region in turn, and of the whole op
// by one that steps over it.
constexpr bool mayAcquire(const EffectSet &set) {
  if (set.reported.contains(Atom::alloc))
    return true;
  for (Kind kind : allOf<Kind>())
    if (!(set.byKind[kind] & detail::takesMemoryOn[kind]).empty())
      return true;
  return false;
}

// Whether memory may be taken while `op` runs, with everything in it.
inline bool mayAcquire(mlir::Operation *op) { return mayAcquire(whole(op)); }

// What an op reports in its function's row beyond its MLIR effects: the
// memory its runtime function, or a call's callee, acquires or gives back
// that no value names.
Row reportedBy(mlir::Operation *op);

// Whether `moved`, with everything in it, may run on the other side of
// `across`, with everything in it: neither may tell.
inline bool mayMoveAcross(mlir::Operation *moved, mlir::Operation *across) {
  return !whole(moved).conflicts(whole(across));
}

} // namespace idr::effects

#endif // IDR_IR_EFFECTS_WHOLE_H
