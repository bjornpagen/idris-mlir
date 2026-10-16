// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The rules the ops on arrays share, each said once: what an array holds at
// an index, where an element moves, where control goes in a region of the
// generating set, what such a region must end in and bind, and the bounds
// of the indices it binds. lib/IR/OpsGenerating.cpp defines them.
#ifndef IDR_IR_ARRAYS_H
#define IDR_IR_ARRAYS_H

#include "idr/IR/IdrDialect.h"

#include "mlir/Interfaces/ValueBoundsOpInterface.h"
#include "llvm/ADT/STLFunctionalExtras.h"

namespace idr::arrays {

// What an array of `array`'s type holds at an index of its `lead` leading
// dimensions: its element when they are all of them, else the cell of the
// dimensions after them.
mlir::Type cellOf(mlir::RankedTensorType array, unsigned lead);

// Whether two arrays agree on their `lead` leading dimensions: the same
// size where both are static, both dynamic otherwise, so that one size
// operand or one operand's dimension gives each.
bool sameLead(mlir::RankedTensorType a, mlir::RankedTensorType b, unsigned lead);

// The elements of `array`, a part of it.
FlowPoint elementsOf(mlir::Value array);

// What a value at an index of an array is: an element, or the elements of
// a cell, a part of the cell.
FlowPoint atIndex(mlir::OpOperand &use);
FlowPoint atIndex(mlir::Value value);

// A region of the generating set is entered from the op and from its own
// end, each time it ends for an index, and left from the op when the
// domain is empty and from its end after the last index.
void generatingSuccessors(mlir::Operation *op,
                          llvm::SmallVectorImpl<mlir::RegionSuccessor> &regions);

// The rule every region of the generating set and of an update keeps: it
// ends in idr.array.yield of `types`, each at any permission where
// `graded` says so, or in ub.unreachable.
mlir::LogicalResult verifyEnd(mlir::Operation *op, mlir::TypeRange types,
                              llvm::function_ref<bool(unsigned)> graded = {});

// The indices a region binds first: `rank` of them, each an index.
mlir::LogicalResult verifyIndices(mlir::Operation *op, unsigned rank);

// An index of the domain is at least 0 and below its dimension's size,
// which `extent` gives.
void boundIndex(mlir::Value value, mlir::Block::BlockArgListType indices,
                llvm::function_ref<mlir::AffineExpr(unsigned)> extent,
                mlir::ValueBoundsConstraintSet &cstr);

} // namespace idr::arrays

#endif // IDR_IR_ARRAYS_H
