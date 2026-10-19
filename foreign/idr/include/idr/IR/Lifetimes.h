// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a value of the frame lifetime (Lifetime::Frame, the grade's third
// part) makes of what it reaches at each use: the rules of the frame, said
// once, which two readers hold. The function verifier holds every value of
// the frame to them on types (verify::lifetimes); idr-rc's stack step
// infers from them the least lifetimes that put each cell it can in its
// frame (lib/Transforms/Stack), so it can never be wrong unnoticed: the
// verifier runs after it.
//
// A cell of the frame dies with the frame, or with the loop iteration that
// made it, when its slot is written again. So a value that may reach one
// is frame itself, and so is what it reaches it through: a field read from
// it, a constructor or a closure that holds it, a value it is forwarded
// into. And it is never:
//   - returned, which its function's result types, never frame, refuse;
//   - given to a parameter of the heap, which the call's types refuse
//     (a parameter of the frame takes a heap value through idr.share);
//   - moved into memory that exists before the op that moves it (the
//     forced state of a memo cell, an array's element, a hole, a cell that
//     is not the frame's: an init of a heap cell);
//   - forwarded by the terminator of a region that runs again, which
//     carries it into the next iteration, whose cells take the same slots;
//   - an operand of a self call in tail position, or in tail position but
//     for a context, which idr-tail-loops and idr-trmc make the next
//     iteration of a loop in the same frame;
//   - an operand of an op that declares no flow, whose moves no reader
//     knows.
#ifndef IDR_IR_LIFETIMES_H
#define IDR_IR_LIFETIMES_H

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Operation.h"
#include "mlir/IR/Value.h"
#include "llvm/ADT/STLFunctionalExtras.h"

#include <cstdint>
#include <variant>

namespace idr::lifetimes {

// `to`, a value the op makes (a result, an argument of a region of its),
// holds what the frame value holds: it is frame too.
struct Carries {
  mlir::Value to;
};

// The frame value moves into the cell `init` fills: the box it makes is of
// its cell's lifetime, which its source decided, so the cell must be the
// frame's.
struct Fills {
  CellInitOp init;
};

// The frame value is argument `index` of `call`: the callee's parameter is
// frame too, which the call's types hold, its argument's being its
// parameter's.
struct Passes {
  CallOp call;
  unsigned index;
};

// Why a frame value may not go where an op takes it.
enum class Escape : std::uint8_t {
  // Returned by its function.
  Returned,
  // Into memory that exists before the op.
  Stored,
  // Forwarded by the terminator of a region that runs again.
  Repeated,
  // An operand of a self call that becomes the next iteration of a loop.
  TailCalled,
  // An operand of an op whose moves no one declares.
  Unknown,
};

// Whether `op` is a self call that becomes the next iteration of a loop in
// the same frame (idr-tail-loops, idr-trmc): its operands are the next
// iteration's parameters, so no parameter of its function is of the frame.
bool loopsInFrame(mlir::Operation *op);

// A short text of an escape, for a diagnostic.
llvm::StringRef describe(Escape escape);

using Edge = std::variant<Carries, Fills, Passes, Escape>;

// Each edge a frame value at an operand of `op` would take, with the value
// it starts from: the moves `op` declares (flowEdgesOf) of every value
// that may be frame (mayBeFrame), the result of an op that carries its
// operand, and the escapes above.
void edgesOf(mlir::Operation *op,
             llvm::function_ref<void(mlir::Value from, const Edge &edge)> each);

} // namespace idr::lifetimes

#endif // IDR_IR_LIFETIMES_H
