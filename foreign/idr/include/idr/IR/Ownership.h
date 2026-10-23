// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What the ownership passes share: which constructor has a cell, which
// memory a store hands a reference to, and what a value was read from. Whether a value is
// static data is its grade's (`static`), read off its type, never searched
// for along its definitions.
#ifndef IDR_IR_OWNERSHIP_H
#define IDR_IR_OWNERSHIP_H

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Value.h"

#include <optional>

namespace idr {

// Whether constructor `tag` of a value of `type` (at any grade) has a cell
// of its own: the family's layout is a cell and the constructor has fields.
// The one place the two cases meet: a cell's con becomes a cell source and
// cell.init, and its take is idr.count.take; any other stays idr.data.con, and
// its take is idr.count.unpack.
bool buildsCell(mlir::Type type, Tag tag);

} // namespace idr

namespace idr::ownership {

// Whether an op of upstream's writes the value `operand` holds into memory
// (a memref.store's value): the memory then holds it, and the reference
// with it.
bool storedBy(mlir::OpOperand &operand);

// The value a field was read from: the operand of an idr.data.field, the
// source of a view of a buffer, or the buffer a counted element is loaded
// from; null for any other value. A match's region binds its scrutinee
// refined, the value itself, and reads nothing from it.
mlir::Value readFrom(mlir::Value value);

// The counted value a view was read from: up through what each step was
// read from (readFrom) and through the values each step is (sourceOf's
// Same, a loan's view among them), never through idr.count.share.
mlir::Value viewRoot(mlir::Value value);

// The owner `value` is a part of, read with no reference of its own (a
// field read, an element view, a lent element), as the op that makes it
// declares its moves: it moves whole out of a part of a value the op only
// reads, and the op neither empties the place it moves out of (a take
// moves what it holds out with its reference) nor makes the value fresh
// (a copy gives it one of its own). None for any other value. Such a part
// is given up with its owner, never on its own.
std::optional<mlir::Value> ownerOfPart(mlir::Value value);

} // namespace idr::ownership

#endif // IDR_IR_OWNERSHIP_H
