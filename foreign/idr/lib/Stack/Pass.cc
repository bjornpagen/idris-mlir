// idr-stack: a box whose cell never leaves its frame is built on the stack.
//
// An `idr.con` of a box gets the unit attribute `idr.stack` when the escape
// analysis (Stack/Escape.h) proves that no reference to its cell outlives the
// frame of the function that builds it, nor the loop iteration that builds
// it. idr-lower then builds the cell in a slot of the function's entry block
// instead of calling the allocator: its header is count 1 with the stack mark
// (IDRIS_RT_STACK_CELL), so counting works on it as on any cell, except that
// when its count reaches 0 its fields are released and its memory is not
// freed, and that it is never exclusive, so no reset reuses its memory for
// a value that could outlive the frame.
//
// A cell larger than `cellLimit` stays on the heap, and so do the cells of
// a function past its frame budget, in the order the function builds them.
// A function that is on a cycle of calls may have many frames live at once,
// each with its slots, so its budget is much smaller.
//
// The marks are the pass's alone: it drops any it finds before it decides.

#include "Lower/Layout.h"
#include "Stack/Cell.h"
#include "Stack/Escape.h"
#include "Stack/Recursion.h"

using namespace mlir;

namespace idr {
#define GEN_PASS_DEF_IDRSTACK
#include "idr/Passes.h.inc"
} // namespace idr

namespace {

using idr::stack::mark;

constexpr unsigned cellLimit = 256;
constexpr unsigned frameLimit = 1024;
constexpr unsigned recursiveFrameLimit = 64;

struct Stack : idr::impl::IdrStackBase<Stack> {
  void runOnOperation() override {
    ModuleOp module = getOperation();
    UnitAttr unit = UnitAttr::get(&getContext());
    module.walk([](idr::ConOp con) { con->removeAttr(mark); });
    idr::stack::Cycles cycles(module);
    idr::stack::Escapes escapes(module, cycles);
    FailureOr<idr::lower::Layouts> layouts = idr::lower::Layouts::of(module);
    if (failed(layouts))
      return signalPassFailure();
    for (auto fn : module.getOps<func::FuncOp>()) {
      unsigned left = cycles.recursive(fn) ? recursiveFrameLimit : frameLimit;
      fn.walk<WalkOrder::PreOrder>([&](idr::ConOp con) {
        if (!isa<idr::BoxType>(con.getType()))
          return;
        ++numBoxes;
        if (escapes.mayEscape(con))
          return;
        unsigned size = layouts->box(idr::lookupCtor(con, con.getCtor())).size;
        if (size > cellLimit || size > left)
          return;
        left -= size;
        con->setAttr(mark, unit);
        ++numCells;
      });
    }
  }
};

} // namespace
