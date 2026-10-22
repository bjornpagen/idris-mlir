// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
//===- Tail.h - What becomes of a function's tail positions ---------------===//
//
// A call in tail position never grows the stack, and a recursion keeps its
// depth on typed frame stacks, never on the native stack. The passes that
// make it so share these declarations:
//   - idr-accumulate: a self call combined in a tail by an operation the
//     runtime defines as exactly associative, with its identity, becomes
//     a tail call carrying the combination so far (an optimization).
//   - idr-trmc: every self call modulo a context (a promise) fills the
//     hole of cells built before it, so it is a tail call of a clone that
//     takes a destination.
//   - idr-frames: every call that is not in tail position, between
//     functions of one cycle of calls, pushes the rest of its code as a
//     frame on a typed, linear, uncounted stack and becomes a tail call;
//     the rest runs when a resume pops the frame (a promise).
//   - idr-tail-loops: a function's self tail calls become one loop.
// Tail position itself is idr/IR/Tail.h's, one fact on each call.
//
//===----------------------------------------------------------------------===//

#ifndef IDR_TRANSFORMS_TAIL_H
#define IDR_TRANSFORMS_TAIL_H

#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/Pass.h"
#include "llvm/ADT/SmallVector.h"

#include <cstdint>
#include <optional>
#include <variant>

namespace idr {
#define GEN_PASS_DECL_IDRACCUMULATE
#define GEN_PASS_DECL_IDRFRAMES
#define GEN_PASS_DECL_IDRTRMC
#define GEN_PASS_DECL_IDRTAILLOOPS
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

namespace idr::tail {

//===----------------------------------------------------------------------===//
// The program graph
//===----------------------------------------------------------------------===//

// `fn`'s row of the program graph as its calls now are: each distinct
// callee and tail kind, with how many calls have it. What idr-trmc and
// idr-frames give the editor for each function they make or change.
template <solver::FunctionNames N>
llvm::SmallVector<solver::Call> callRow(FuncOp fn, const N &names) {
  llvm::SmallVector<solver::Call> row;
  fn.walk([&](CallOp call) {
    solver::FunctionId callee = names.id(call.getCalleeAttr());
    auto *same = llvm::find_if(row, [&](const solver::Call &c) {
      return c.callee == callee && c.kind == call.getTailKind();
    });
    if (same != row.end())
      ++same->sites;
    else
      row.push_back({callee, call.getTailKind(), 1});
  });
  return row;
}

//===----------------------------------------------------------------------===//
// Accumulators
//===----------------------------------------------------------------------===//

// Which operand of the combination the self call's result is: the clone
// keeps the combination on that side, so the operation need not commute.
enum class Side : std::uint8_t { Left, Right };

// A self call whose one result `combine`, the tail, takes with another
// value that no self call computes: `f(...) ⊕ g` or `g ⊕ f(...)`.
struct Combined {
  CallOp call;
  mlir::Operation *combine;
  Side side;
};
// A self call of a function of accumulator tails: a tail call, which
// passes the combination on unchanged, or one a tail combines.
using Site = std::variant<CallOp, Combined>;

// What becomes of a function whose every self call is a site and one at
// least is combined, every combination by one operation on one side (or
// by one that commutes): its sites, the operation (the first site's op,
// which the clone copies to combine), its identity, and the side.
struct Accumulator {
  llvm::SmallVector<Site> sites;
  mlir::Operation *combine;
  mlir::TypedAttr identity;
  Side side;
};

// `fn`'s accumulator, or none.
std::optional<Accumulator> accumulatorOf(FuncOp fn);

//===----------------------------------------------------------------------===//
// Frames
//===----------------------------------------------------------------------===//

// What a component's frames are, before the family is made: its rows (the
// distinct result types of its functions, each a type a frame may await),
// and each kind of frame: the row it awaits (its callee's), the row its
// rest gives (its owner's, the frame below's), and the values it holds.
struct FrameKind {
  unsigned awaits;
  unsigned continues;
  llvm::SmallVector<mlir::Type> held;
};

// One family per component, indexed by the row a frame awaits, so a frame
// of the wrong type cannot be on top where a value of a row is given: its
// first constructors are the base frames, one per row, each holding the
// destinations of a wrapper's answer; then one constructor per kind,
// holding its values and the stack below it. Laid out as a frame stack
// (linear, uncounted, contiguous). Its other members are the answers, one
// per row, a cell of one constructor holding the row's values, which a
// wrapper keeps on its own frame.
struct FramesFamily {
  FamilyAttr group;
  // The stack awaiting each row, and each row's answer.
  llvm::SmallVector<DataType> stacks;
  llvm::SmallVector<DataType> answers;
  unsigned rows;

  Tag base(unsigned row) const { return Tag{row}; }
  Tag kind(unsigned index) const { return Tag{rows + index}; }
};

FramesFamily declareFrames(mlir::MLIRContext *ctx, mlir::StringAttr label, mlir::Location loc,
                           llvm::ArrayRef<llvm::SmallVector<mlir::Type, 1>> rows,
                           llvm::ArrayRef<FrameKind> kinds);

} // namespace idr::tail

#endif // IDR_TRANSFORMS_TAIL_H
