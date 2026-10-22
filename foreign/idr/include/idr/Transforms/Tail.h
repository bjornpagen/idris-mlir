// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
//===- Tail.h - What becomes of a function's tail positions ---------------===//
//
// A call in tail position never grows the stack, and a recursion keeps its
// depth on typed frame stacks, never on the native stack. The passes that
// make it so share these declarations:
//   - idr-accumulate: a self call combined in a tail by an operation the
//     runtime defines as exactly associative, with its identity, or by the
//     short circuit `&&` and `||` are, becomes a tail call carrying the
//     combination so far (an optimization).
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

#include "idr/IR/IdrDialect.h"
#include "idr/Support/Footprint.h"

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
// Accumulators
//===----------------------------------------------------------------------===//

// Which operand of the combination the self call's result is: the clone
// keeps the combination on that side, so the operation need not commute.
enum class Side : std::uint8_t { Left, Right };

// An op the specification calls exactly associative, with its identity
// (the attribute its dialect materializes at the combination's type,
// untyped for a big), held as what the op is, so the clone makes it again
// wherever it combines, whatever became of the op it was read off.
struct Law {
  mlir::OperationName name;
  mlir::Attribute properties;
  mlir::DictionaryAttr discardable;
  mlir::Attribute identity;
};

// `&&` and `||` as they reach the pass: base's functions of a lazy second
// operand, inlined, are a match on the first operand, of a type of two
// constructors that hold nothing, whose region for one, the absorbing
// constructor (`&&`'s False, `||`'s True), gives it back, and whose region
// for the other gives the second operand. "a if a is the absorbing
// constructor, else b" is exactly associative, the other constructor its
// identity, and reads b only where a does not decide. Held as the two
// constructors and the refined scrutinee each region binds, from which the
// clone builds the match again.
struct ShortCircuit {
  Tag absorbing;
  Tag identity;
  mlir::Type absorbingType;
  mlir::Type identityType;
};

// The operation a tail combines a self call's result by.
using Combination = std::variant<Law, ShortCircuit>;

// A self call whose one result `combine`, the tail, takes with another
// value that no self call computes, by `by`: `f(...) ⊕ g` or `g ⊕ f(...)`,
// where `combine` is the law's op or the short circuit's match (the call
// then on the left).
struct Combined {
  CallOp call;
  mlir::Operation *combine;
  Combination by;
  Side side;
};
// A self call of a function of accumulator tails: a tail call, which
// passes the combination on unchanged, or one a tail combines.
using Site = std::variant<CallOp, Combined>;

// What becomes of a function whose every self call is a site and one at
// least is combined, every combination by one operation on one side (or
// by one that commutes), at the function's result type: its sites, the
// operation, and the side.
struct Accumulator {
  llvm::SmallVector<Site> sites;
  Combination by;
  Side side;
};

// `fn`'s accumulator, or none.
std::optional<Accumulator> accumulatorOf(FuncOp fn);

// The one constructor `value` is, where its type says so through what
// gives it on with no run-time work: a constructor built, a constant, a
// match's refined scrutinee. None where its type leaves more than one.
std::optional<Tag> statedConstructor(mlir::Value value);

//===----------------------------------------------------------------------===//
// Frames
//===----------------------------------------------------------------------===//

// Every function a component runs on its stack takes the component's
// lifetimes alike, the same kinds in the same order, and passes them on at
// each of its tails: so a lifetime never goes into a frame, where it could
// be read back stale or name no place, and each scoped value a frame holds,
// or a row gives, lives in one of them, named by its place among them.
//
// A row: the types of the values a frame awaits (the results of a function
// of the component), and for each scoped one, in order, the place of the
// lifetime it lives in among the component's lifetimes.
struct Row {
  llvm::SmallVector<mlir::Type, 1> types;
  llvm::SmallVector<unsigned, 1> livesIn;
  bool operator==(const Row &) const = default;
};

// What a component's frames are, before the family is made: its rows, and
// each kind of frame: the row it awaits (its callee's), the row its rest
// gives (its owner's, the frame below's), the values it holds, and for
// each scoped one, in order, the place of the lifetime it lives in.
struct FrameKind {
  unsigned awaits;
  unsigned continues;
  llvm::SmallVector<mlir::Type> held;
  llvm::SmallVector<unsigned> heldIn;
};

// One family per component, indexed by the row a frame awaits, so a frame
// of the wrong type cannot be on top where a value of a row is given: its
// first constructors are the base frames, one per row, each holding one
// destination per result of the row, at the result's whole type, the slots
// of the wrapper that started the run; then one constructor per kind,
// holding its values and the stack below it. Laid out as a frame stack
// (linear, uncounted, contiguous).
struct FramesFamily {
  FamilyAttr group;
  // The stack awaiting each row.
  footprint::Vector<DataType> stacks;
  unsigned rows;

  Tag base(unsigned row) const { return Tag{row}; }
  Tag kind(unsigned index) const { return Tag{rows + index}; }
};

FramesFamily declareFrames(mlir::MLIRContext *ctx, mlir::StringAttr label, mlir::Location loc,
                           llvm::ArrayRef<Row> rows, llvm::ArrayRef<FrameKind> kinds);

} // namespace idr::tail

#endif // IDR_TRANSFORMS_TAIL_H
