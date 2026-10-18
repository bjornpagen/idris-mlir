// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-rc-stack: a cell that never leaves its frame is made on the stack.
//
// An idr.cell.new becomes idr.cell.stack, as upstream's
// promote-buffers-to-stack makes a memref.alloc a memref.alloca, when the
// escape analysis proves that no reference to the cell outlives the frame
// of the function that makes it, nor the loop iteration that makes it.
// idr-lower then makes the cell in a slot of the function's entry block
// instead of calling the allocator: its header is count 1 with the stack
// mark (IDRIS_RT_STACK_CELL), so counting works on it as on any cell,
// except that when its count reaches 0 its fields are released and its
// memory is not freed. The step runs before reuse and exclusivity are
// decided, which read the source of every cell: a stack cell is never
// recycled for a value that could outlive the frame, and never exclusive.
//
// A cell larger than a limit stays on the heap, and so do the cells of a
// function past its frame budget, in the order the function makes them. A
// function that is on a cycle of calls may have many frames live at once,
// each with its slots, so its budget is much smaller.
#include "idr/Analysis/Escapes.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/TypeGraph.h"
#include "idr/Support/Actions.h"
#include "idr/Transforms/Pipeline.h"
#include "idr/Transforms/Stack.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/SymbolTable.h"
#include "llvm/ADT/SmallVector.h"

namespace idr {
#define GEN_PASS_DEF_IDRRCSTACK
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

// idr-rc-stack puts one cell on the stack; the unit is the cell.
struct StackCellAction : idr::support::TaggedAction<StackCellAction> {
  using TaggedAction::TaggedAction;
  static constexpr llvm::StringLiteral tag = "idr-stack-cell";
};

struct Stack : idr::impl::IdrRcStackBase<Stack> {
  void runOnProgram(idr::ProgramOp program) override {
    const idr::Layouts &layouts = getAnalysis<idr::Layouts>();
    const idr::Escapes &escapes = getAnalysis<idr::Escapes>();
    // The decision, on the program as it stands: the cells that go on the
    // stack, each taking its size from what is left of its frame.
    SmallVector<idr::CellNewOp> toStack;
    for (idr::FuncOp fn : program.getOps<idr::FuncOp>()) {
      unsigned left = escapes.recursive(fn) ? recursiveStackFrameLimit : stackFrameLimit;
      fn.walk<WalkOrder::PreOrder>([&](idr::CellNewOp cell) {
        ++numBoxes;
        if (escapes.mayEscape(cell))
          return;
        idr::CellType type = cell.getCell().getType();
        unsigned size = layouts.box(type.getBox().getData()).cell(type.getTag()).size;
        if (size > stackCellLimit || size > left)
          return;
        left -= size;
        toStack.push_back(cell);
      });
    }

    // The frame budget a skipped cell took stays taken: less is on the
    // stack, never anything wrong.
    IRRewriter rewriter(&getContext());
    unsigned stacked = 0;
    for (idr::CellNewOp cell : toStack)
      stacked += idr::support::perform<StackCellAction>(cell, [&] {
        rewriter.replaceOpWithNewOp<idr::CellStackOp>(cell, cell.getCell().getType());
      });
    numStackCells += stacked;
    if (stacked == 0)
      return markAllAnalysesPreserved();
    // A cell's source changes what an op does to memory, which the
    // ownership analyses read, and nothing a data type or a symbol says.
    markAnalysesPreserved<idr::TypeGraph, idr::Layouts, SymbolTable>();
  }
};

} // namespace
