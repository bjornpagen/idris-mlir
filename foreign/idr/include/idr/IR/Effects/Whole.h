// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// An op's effects as a set, the untyped half of the one query API: an
// `Operation *` makes one interface dispatch, ours (an op's own effects as
// one set) or, for an op of another dialect, upstream's, whose instances
// are folded once into a set. Every question about an op's effects that
// names no value asks here: what it does, alone or with everything in its
// regions, what it adds to its function's row, and whether two ops may
// trade places.
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
