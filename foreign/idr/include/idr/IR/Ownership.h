// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What the owned stage's verifier and the ownership passes share: which
// constructor has a cell, what a use does with a reference, and which
// values no count reaches. Whether a function is in the owned stage is its
// program's stage (ProgramOp).
#ifndef IDR_IR_OWNERSHIP_H
#define IDR_IR_OWNERSHIP_H

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Value.h"

#include <optional>

namespace idr {

// Whether constructor `tag` of a value of `type` (at any grade) has a cell
// of its own: the value is a box and the constructor is not an atom. The
// one place the two cases meet: a cell's con becomes cell.new and
// cell.init after idr-rc, and its take is idr.take; any other con stays
// idr.con, and its take is idr.unpack.
bool buildsCell(mlir::Type type, Tag tag);

} // namespace idr

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

// Whether an op of upstream's writes the value `operand` holds into memory
// (a memref.store's value): the memory then holds it, and the reference
// with it.
bool storedBy(mlir::OpOperand &operand);

// Whether `value` is static data its op makes from nothing a count
// reaches: a constant, poison, a small big, a global's buffer. The op has
// no regions, is pure, and reads no reference. idr-rc grades such a value
// once (gradeStatic), and what is read from it carries the static lifetime
// in its grade; this asks the op alone, for what no grade can say (a
// buffer of upstream's) or a pass made after counting.
bool madeStatic(mlir::Value value);

// The value a field was read from: the operand of an idr.field, the
// scrutinee of the match whose case region binds it, the source of a view
// of a buffer, or the buffer a counted element is loaded from; null for any
// other value. A default binds the scrutinee itself, and reads nothing
// from it.
mlir::Value readFrom(mlir::Value value);

// What `value` lives as long as, as counting and borrow inference read it:
// what it was read from (readFrom), or, for the argument a match's default
// region binds, the match's scrutinee. readFrom gives none for that
// argument: it is the scrutinee itself (sourceOf's Same), no field read
// from it. But the region reads it while the match holds the scrutinee, as
// a case reads a field, so it lives as long as the scrutinee. None for any
// other value; a step of definitionChain.
std::optional<mlir::Value> readThrough(mlir::Value value);

// The owned value a view was read from: up through what each step was read
// from (readFrom) and through the values each step is (sourceOf's Same),
// never through idr.share.
mlir::Value viewRoot(mlir::Value value);

// Whether `view` is static data that reaches no cell but atoms, which is in
// every exclusive tree.
bool reachesOnlyAtoms(mlir::Value view);

} // namespace idr::ownership

#endif // IDR_IR_OWNERSHIP_H
