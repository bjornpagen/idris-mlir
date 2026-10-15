// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What the owned stage's verifier and the ownership passes share: what a
// use does with a reference, and which values no count reaches. Whether a
// function is in the owned stage is its program's stage (ProgramOp).
#ifndef IDR_IR_OWNERSHIP_H
#define IDR_IR_OWNERSHIP_H

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Value.h"

namespace idr::ownership {

// What a use does with a reference in the owned stage: consumes one, or
// only needs the value to be alive.
enum class Use { Consume, Borrow };

// The op that uses `operand` declares which (idr::consumes): returns, scf's
// yields, a call's owned parameters and the operands ODS names beside each
// idr op consume; everything else borrows, the closure an apply calls
// included. A force is placement's: idr-rc gives it its cell owned where
// the cell dies, and there it takes the cell over; anywhere else it reads a
// view.
Use useOf(mlir::OpOperand &operand);

// Whether `value` is static: a constant, poison, or a field read from one.
bool isStatic(mlir::Value value);

// The value a field was read from: the operand of an idr.field, the
// scrutinee of the match whose region binds it, the source of a view of a
// buffer, or the buffer a counted element is loaded from; null for any
// other value.
mlir::Value readFrom(mlir::Value value);

// The owned value a view was read from: through idr.borrow, idr.field,
// lin.enter, lin.use and the fields a match's region binds.
mlir::Value viewRoot(mlir::Value value);

// Whether `view` is static data that reaches no cell but atoms, which is in
// every exclusive tree.
bool reachesOnlyAtoms(mlir::Value view);

} // namespace idr::ownership

#endif // IDR_IR_OWNERSHIP_H
