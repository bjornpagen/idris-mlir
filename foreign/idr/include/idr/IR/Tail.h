// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Where what an op computes is what its function returns: the last op
// before the function's idr.return, or before the idr.yield of a match
// region whose match is in tail position itself, when the terminator
// passes on exactly the op's results. A self call there becomes the next
// iteration of a loop in the same frame (idr-tail-loops), and borrow
// inference, the rules of the frame (Lifetimes.h) and the stack's
// recursion rule read the same position, so it is defined once, here, for
// all of them.
#ifndef IDR_IR_TAIL_H
#define IDR_IR_TAIL_H

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Block.h"
#include "mlir/IR/Operation.h"
#include "llvm/ADT/SmallVector.h"

#include <optional>

namespace idr::tail {

// Whether `block` ends a tail position: its terminator is the function's
// idr.return, or the idr.yield of a match in tail position. The one test
// of where a tail ends.
bool endsTail(mlir::Block &block);

// Whether the results of `op` pass unchanged to its function's return.
bool inTailPosition(mlir::Operation *op);

// Whether `terminator` is a return or a match's yield and passes on
// exactly the results of the op before it.
bool passesOnPrevious(mlir::Operation *terminator);

// Whether `op` is a match whose regions may hold tail positions.
bool isTailMatch(mlir::Operation *op);

// The match in tail position right before `terminator`, or null.
mlir::Operation *tailMatch(mlir::Operation *terminator);

// Whether `op` is a call of `fn` itself, by name.
bool isSelfCall(mlir::Operation *op, FuncOp fn);

// A tail modulo a context: a self call whose result the value the tail
// returns holds, somewhere inside it, and nothing else reaches. The result
// goes, through grades, into a field of a fresh cell, the holed cell; the
// holed cell's box is then moved into parts of values (fields of cells,
// fields of constructors without a cell), read back out as the part it is
// (idr.unpack, idr.field of such a constructor), regraded, and carried
// through a match's yield to its result, until the tail returns the value
// that holds it. It is never read whole: no match, no field read, no call,
// no copy and no drop of it. idr-trmc builds the holed cell with the field
// a hole and calls a clone with its destination once the returned value is
// built, so the call is the last thing the tail does; it runs after idr-rc,
// when every box a constructor with fields builds is a cell written by
// idr.cell.init. One constructor around the call is the context whose holed
// cell is the returned one.
//
// The result is used once on each path: once in the block, or once in each
// region of the matches it is carried across, one of which runs. So there
// is a holed cell per such region (`holes`), and each match whose regions
// hold one (`joins`, innermost first) gives that region's destination as
// one more result: exactly one destination arrives where the tail ends.
struct Hole {
  CellInitOp init;
  unsigned index;
};
struct Context {
  CallOp call;
  llvm::SmallVector<Hole, 1> holes;
  // The grades between the call's result and its holes, in the order the
  // walk met them: a grade has no runtime form, and goes with the call.
  llvm::SmallVector<mlir::Operation *, 2> grades;
  llvm::SmallVector<mlir::Operation *, 1> joins;
};

// The tail modulo a context of `block` in `fn`: a self call in the block
// whose result the block's terminator passes on inside a context, and that
// may run right before that terminator (mayRunAt).
std::optional<Context> contextAt(mlir::Block &block, FuncOp fn);

// Whether `call` is the self call of a tail modulo a context in a block in
// tail position: idr-trmc writes its result into the value the block
// returns, which it builds before the call.
bool inTailPositionModuloContext(CallOp call);

} // namespace idr::tail

#endif // IDR_IR_TAIL_H
