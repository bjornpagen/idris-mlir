// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What the closure ops (lib/IR/OpsClosures.cpp) tell the passes that build
// them: the types at which a memo cell's exchange moves its captures out,
// which idr.memo.run's region binds and idr.memo.take gives.
#ifndef IDR_IR_CLOSURES_H
#define IDR_IR_CLOSURES_H

#include "mlir/IR/Types.h"
#include "llvm/ADT/SmallVector.h"

#include <optional>

namespace idr {

// The captures of the label `cell`, a memo cell refined to one state, is
// refined to, each at the type an exchange moves it out at. The exchange
// empties the capture's field, so the capture holds the reference the
// field held, whatever holds the cell: its field's carrier at the cell's
// indices, used as the field declares (the field gives its value up once,
// so the cell's uses multiply nothing), counted, and claiming nothing of
// its sharing but what a re-pack of its slot that builds makes fresh. A
// pass may prove more of a capture than that, or learn where what it holds
// lives, and the capture then stands at that hold: the carrier and the
// uses are the field's, the hold is the capture's own. None where the
// refinement determines no binders to read the fields at.
std::optional<llvm::SmallVector<mlir::Type>> capturesMovedOut(mlir::Type cell);

} // namespace idr

#endif // IDR_IR_CLOSURES_H
