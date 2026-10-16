// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-stack: a box whose cell never leaves its frame is built on the stack.
//
// An idr.con of a box gets its `stack` property when the escape analysis
// proves that no reference to its cell outlives the frame of the function
// that builds it, nor the loop iteration that builds it. idr-lower then
// builds the cell in a slot of the function's entry block instead of
// calling the allocator: its header is count 1 with the stack mark
// (IDRIS_RT_STACK_CELL), so counting works on it as on any cell, except
// that when its count reaches 0 its fields are released and its memory is
// not freed, and that it is never exclusive, so no reset reuses its memory
// for a value that could outlive the frame.
//
// A cell larger than a limit stays on the heap, and so do the cells of a
// function past its frame budget, in the order the function builds them. A
// function that is on a cycle of calls may have many frames live at once,
// each with its slots, so its budget is much smaller.
//
// The property is the pass's alone to set: every con is decided again, and
// one the decision does not keep goes back to the heap.
#include "idr/Transforms/Stack.h"

#include "idr/Analysis/Escapes.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/TypeGraph.h"
#include "idr/Support/Actions.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/SymbolTable.h"
#include "llvm/ADT/SmallVector.h"

namespace idr {
#define GEN_PASS_DEF_IDRSTACK
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace {

// The size policies of the stack, in bytes: the largest cell a frame
// holds, and how much of a frame a function's cells take, much less for a
// function on a cycle of calls, which may have many frames live at once.
// They bound how far a frame grows, never what compiles: a cell they leave
// on the heap is the same cell there.
constexpr unsigned stackCellLimit = 256;
constexpr unsigned stackFrameLimit = 1024;
constexpr unsigned recursiveStackFrameLimit = 64;

// idr-stack puts one constructor's cell on the stack; the unit is the con.
struct StackCellAction : idr::support::TaggedAction<StackCellAction> {
  using TaggedAction::TaggedAction;
  static constexpr llvm::StringLiteral tag = "idr-stack-cell";
};

struct Stack : idr::impl::IdrStackBase<Stack> {
  void runOnOperation() override {
    idr::ProgramOp program = getOperation();
    const idr::Layouts &layouts = getAnalysis<idr::Layouts>();
    const idr::Escapes &escapes = getAnalysis<idr::Escapes>();
    // The decision, on the program as it stands: the cons whose property
    // is to change, those the analysis no longer proves back to the heap and
    // those it newly proves onto the stack.
    SmallVector<idr::ConOp> toHeap, toStack;
    for (idr::FuncOp fn : program.getOps<idr::FuncOp>()) {
      unsigned left = escapes.recursive(fn) ? recursiveStackFrameLimit : stackFrameLimit;
      // Whether `con` goes on the stack, which takes its size from what is
      // left of the frame.
      auto onStack = [&](idr::ConOp con) {
        if (!isa<idr::BoxType>(con.getResult().getType()))
          return false;
        ++numBoxes;
        if (escapes.mayEscape(con))
          return false;
        unsigned size = layouts.box(con.getDataType(), con.getTag()).size;
        if (size > stackCellLimit || size > left)
          return false;
        left -= size;
        return true;
      };
      fn.walk<WalkOrder::PreOrder>([&](idr::ConOp con) {
        bool marked = onStack(con);
        if (marked == con.getStack()) {
          numCells += marked;
          return;
        }
        (marked ? toStack : toHeap).push_back(con);
      });
    }

    // A cell the analysis no longer proves goes back to the heap whatever an
    // action handler says, so only putting a cell on the stack is an action.
    // The frame budget a skipped cell took stays taken: less is on the
    // stack, never anything wrong.
    IRRewriter rewriter(&getContext());
    for (idr::ConOp con : toHeap)
      rewriter.modifyOpInPlace(con, [&] { con.setStack(false); });
    unsigned stacked = 0;
    for (idr::ConOp con : toStack)
      stacked += idr::support::perform<StackCellAction>(
          con, [&] { rewriter.modifyOpInPlace(con, [&] { con.setStack(true); }); });
    numCells += stacked;
    if (toHeap.empty() && stacked == 0)
      return markAllAnalysesPreserved();
    // The property changes what a con does to memory, which the ownership
    // analyses read, and nothing a data type or a symbol says.
    markAnalysesPreserved<idr::TypeGraph, idr::Layouts, SymbolTable>();
  }
};

} // namespace
