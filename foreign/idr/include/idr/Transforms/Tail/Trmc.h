// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What the units of idr-trmc share (lib/Transforms/Tail): the rewrite of a
// function's tails, which builds each context's cells before what fills
// their holes (TrmcRewrite), and the pass that reads each function's
// contexts and makes its clone (Trmc).
#ifndef IDR_TRANSFORMS_TAIL_TRMC_H
#define IDR_TRANSFORMS_TAIL_TRMC_H

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Tail.h"

#include "mlir/IR/IRMapping.h"
#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/ArrayRef.h"

#include <variant>

namespace idr::tail::trmc {

// A context mapped into a copy of its function.
Context mapped(const Context &context, const mlir::IRMapping &mapping);

// Where a value given at a tail goes: on, as the function's first level
// returns it, or into a destination.
struct Given {};
struct Written {
  mlir::Value dest;
};
using Target = std::variant<Given, Written>;

// What a context's step made a value: the hole's cell, a cell or a part
// further out, or a part read back out of a value laid out inline.
struct Hole {
  Into into;
};
struct Outer {
  Into into;
};
struct Part {
  ReadBack read;
};
using Making = std::variant<std::monostate, Hole, Outer, Part>;

// The rewrite of one function's tails, the function's first level or its
// clone: `contexts` are that function's, `fn` the recursion whose self
// calls fill holes, `clone` the function they call instead.
class Rewrite {
public:
  Rewrite(mlir::RewriterBase &rewriter, FuncOp fn, FuncOp clone, llvm::ArrayRef<Context> contexts)
      : rewriter(rewriter), fn(fn), clone(clone), contexts(contexts) {}

  // `value`, given at operand `position` of `terminator` at a tail, goes
  // to `target`. Fails, reported, on a context it cannot build.
  mlir::LogicalResult give(mlir::Value value, mlir::Operation *terminator, unsigned position,
                           Target target);

private:
  Making makerOf(mlir::Value value) const;
  // Rebuilds the hole's cell with its field a hole: its destination.
  mlir::Value makeHole(const Into &hole);
  // The ops after `producer` in its block, its terminator aside, moved
  // before it, in order: the context's cells and what their other fields
  // need, which the rule proved may run there. The changes of grade of the
  // producer's own results go, which the hole no longer reads.
  void buildBefore(mlir::Operation *producer);
  // `call` made a call of the clone that fills `dest`. Its kind is decided
  // once the function is whole (decide), where its place is final.
  void fillByCall(CallOp call, mlir::Value dest);
  // The region op `rejoin`'s result `position` filled in each region, and
  // the op made again without that result.
  mlir::LogicalResult fillByRegions(mlir::Operation *rejoin, unsigned position, mlir::Value dest);
  // `terminator` forwards nothing at `position`; the changes of grade only
  // that operand read go. The op whose region it ends drops that result
  // once every region has (fillByRegions), and the clone its own at last.
  void dropForwarded(mlir::Operation *terminator, unsigned position);

  mlir::RewriterBase &rewriter;
  FuncOp fn;
  FuncOp clone;
  llvm::ArrayRef<Context> contexts;
};

} // namespace idr::tail::trmc

#endif // IDR_TRANSFORMS_TAIL_TRMC_H
