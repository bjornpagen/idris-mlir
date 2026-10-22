// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Where an op ends a reference and where it begins a value, as its
// declaration says: whether it takes over an operand's reference, freeing
// its count, whether it allocates a value, a fresh one of its own, and
// whether it acquires memory, for one value or any. Read off the op's own
// declaration, a call's included, never its callee's.
#ifndef IDR_IR_EFFECTS_CONSUMPTION_H
#define IDR_IR_EFFECTS_CONSUMPTION_H

#include "mlir/IR/Operation.h"
#include "mlir/IR/Value.h"

namespace idr::effects {

// Whether `operand`'s op takes over the reference its value holds: it frees
// the count of that operand.
bool consumes(mlir::OpOperand &operand);

// Whether `op` allocates `value`, a fresh value of its own.
bool allocates(mlir::Operation *op, mlir::Value value);

// Whether `op` acquires the memory `value` lives in, on the heap or in a
// frame: narrower than `allocates`, which a fresh identity also answers.
bool acquires(mlir::Operation *op, mlir::Value value);

// Whether `op` acquires memory for any value, on the heap or in a frame, by
// the same reading as the form above.
bool acquires(mlir::Operation *op);

} // namespace idr::effects

#endif // IDR_IR_EFFECTS_CONSUMPTION_H
