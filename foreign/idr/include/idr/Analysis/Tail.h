// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Where what an op computes is what its function returns: the last op
// before the function's idr.return, or before the idr.yield of a match
// region whose match is in tail position itself, when the terminator
// passes on exactly the op's results. A self call there becomes the next
// iteration of a loop in the same frame (idr-tail-loops), and borrow
// inference and the stack's escape and recursion rules read the same
// position, so it is defined once, here, for all of them.
#ifndef IDR_ANALYSIS_TAIL_H
#define IDR_ANALYSIS_TAIL_H

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Block.h"
#include "mlir/IR/Operation.h"
#include "llvm/ADT/SmallVector.h"

#include <optional>
#include <variant>

namespace idr::tail {

// Whether the results of `op` pass unchanged to its function's return.
bool inTailPosition(mlir::Operation *op);

// Whether `terminator` ends a tail position and passes on exactly the
// results of the op before it.
bool passesOnPrevious(mlir::Operation *terminator);

// Whether `op` is a match whose regions may hold tail positions.
bool isTailMatch(mlir::Operation *op);

// The match in tail position right before `terminator`, or null.
mlir::Operation *tailMatch(mlir::Operation *terminator);

// Whether `op` is a call of `fn` itself, by name.
bool isSelfCall(mlir::Operation *op, FuncOp fn);

// A box a tail builds: a constructor, or one built in a reused cell. Both
// have the same fields, holes and destinations, so what reads one reads
// either.
using Built = std::variant<ConOp, ReuseOp>;

// The op of `built`.
mlir::Operation *opOf(const Built &built);

// A tail modulo constructor: the self call whose result is field `index`
// of the box `built`, which the block's terminator passes on. The result
// may change its grade on its way to the field (`grades`, nearest the
// field first): a grade has no runtime form, and goes with the call.
struct Modulo {
  CallOp call;
  Built built;
  unsigned index;
  llvm::SmallVector<mlir::Operation *, 2> grades;
};

// The tail modulo constructor of `block` in `fn`: the constructor of a box
// right before its terminator, and a self call in the block whose one
// result reaches a field of it, with only ops between them that neither
// touch memory nor can fail, which the call then moves past.
std::optional<Modulo> moduloAt(mlir::Block &block, FuncOp fn);

// Whether `call` is the self call of a tail modulo constructor in a block
// in tail position: idr-trmc writes its result into the constructor the
// block returns, which it builds before the call.
bool inTailPositionModuloConstructor(CallOp call);

} // namespace idr::tail

#endif // IDR_ANALYSIS_TAIL_H
