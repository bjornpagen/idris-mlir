// idr-stack: a box whose cell never leaves its frame is built on the stack.
//
// An idr.con of a box gets the dialect's `stack` mark when the escape
// analysis proves that no reference to its cell outlives the frame of the
// function that builds it, nor the loop iteration that builds it. idr-lower
// then builds the cell in a slot of the function's entry block instead of
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
// The marks are the pass's alone: every mark is decided again, and one the
// decision does not keep is dropped.
#include "idr/Transforms/Stack.h"

#include "idr/Analysis/Escapes.h"
#include "idr/Analysis/Holds.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Symbols.h"
#include "idr/IR/TypeGraph.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/SymbolTable.h"
#include "llvm/ADT/SmallVector.h"

namespace idr {
#define GEN_PASS_DEF_IDRSTACK
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace {

constexpr unsigned cellLimit = 256;
constexpr unsigned frameLimit = 1024;
constexpr unsigned recursiveFrameLimit = 64;

struct Stack : idr::impl::IdrStackBase<Stack> {
  void runOnOperation() override {
    ModuleOp module = getOperation();
    const idr::Layouts &layouts = getAnalysis<idr::Layouts>();
    if (failed(layouts.valid()))
      return signalPassFailure();
    SymbolTable &symbols = getAnalysis<SymbolTable>();
    const idr::Escapes &escapes = getAnalysis<idr::Escapes>();
    if (failed(escapes.solved())) {
      module.emitError("internal error: idr-stack's escape analysis did not reach its fixpoint");
      return signalPassFailure();
    }
    idr::IdrDialect::StackAttrHelper stack(&getContext());

    // The decision, on the module as it stands: the cons whose mark is to
    // change.
    SmallVector<std::pair<idr::ConOp, bool>> changes;
    for (idr::FuncOp fn : module.getOps<idr::FuncOp>()) {
      unsigned left = escapes.recursive(fn) ? recursiveFrameLimit : frameLimit;
      fn.walk<WalkOrder::PreOrder>([&](idr::ConOp con) {
        bool marked = false;
        if (isa<idr::BoxType>(con.getType())) {
          ++numBoxes;
          if (!escapes.mayEscape(con)) {
            unsigned size = layouts.box(idr::lookupCtor(symbols, con.getCtor())).size;
            if (size <= cellLimit && size <= left) {
              left -= size;
              marked = true;
              ++numCells;
            }
          }
        }
        if (marked != stack.isAttrPresent(con))
          changes.emplace_back(con, marked);
      });
    }
    if (changes.empty())
      return markAllAnalysesPreserved();

    IRRewriter rewriter(&getContext());
    UnitAttr unit = rewriter.getUnitAttr();
    for (auto [con, marked] : changes)
      rewriter.modifyOpInPlace(con, [&] {
        if (marked)
          stack.setAttr(con, unit);
        else
          stack.removeAttr(con);
      });
    // A mark changes what a con does to memory, which the ownership
    // analyses read, and nothing a declaration or a symbol says.
    markAnalysesPreserved<idr::Holds, idr::TypeGraph, idr::Layouts, SymbolTable>();
  }
};

} // namespace
