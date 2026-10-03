// idr.stack:mark: idr-stack's decision. A box whose cell never leaves its
// frame is built on the stack.
//
// An `idr.con` of a box gets the unit attribute `idr.stack` when the escape
// analysis (idr.stack:escape) proves that no reference to its cell outlives
// the frame of the function that builds it, nor the loop iteration that
// builds it. idr-lower then builds the cell in a slot of the function's entry
// block instead of calling the allocator: its header is count 1 with the
// stack mark (IDRIS_RT_STACK_CELL), so counting works on it as on any cell,
// except that when its count reaches 0 its fields are released and its
// memory is not freed, and that it is never exclusive, so no reset reuses
// its memory for a value that could outlive the frame.
//
// A cell larger than a limit stays on the heap, and so do the cells of a
// function past its frame budget, in the order the function builds them. A
// function that is on a cycle of calls may have many frames live at once,
// each with its slots, so its budget is much smaller.
//
// The marks are the pass's alone: it drops any it finds before it decides.
export module idr.stack:mark;

import idr.mlir;
import idr.dialect;
import idr.layout;

import :escape;
import :recursion;

using namespace mlir;

namespace idr::stack {

namespace {

using idr::layout::stackMark;

constexpr unsigned cellLimit = 256;
constexpr unsigned frameLimit = 1024;
constexpr unsigned recursiveFrameLimit = 64;

} // namespace

} // namespace idr::stack

export namespace idr::stack {

// What `mark` saw: the cons of boxes, and those it marked.
struct Marked {
  uint64_t boxes = 0;
  uint64_t cells = 0;
};

// Marks the cons of `module` whose cells live in their frame. Fails when the
// module's values have no layout.
FailureOr<Marked> mark(ModuleOp module) {
  Marked marked;
  UnitAttr unit = UnitAttr::get(module.getContext());
  module.walk([](idr::ConOp con) { con->removeAttr(stackMark); });
  Cycles cycles(module);
  Escapes escapes(module, cycles);
  FailureOr<idr::layout::Layouts> layouts = idr::layout::Layouts::of(module);
  if (failed(layouts))
    return failure();
  for (auto fn : module.getOps<func::FuncOp>()) {
    unsigned left = cycles.recursive(fn) ? recursiveFrameLimit : frameLimit;
    fn.walk<WalkOrder::PreOrder>([&](idr::ConOp con) {
      if (!isa<idr::BoxType>(con.getType()))
        return;
      ++marked.boxes;
      if (escapes.mayEscape(con))
        return;
      unsigned size = layouts->box(idr::lookupCtor(con, con.getCtor())).size;
      if (size > cellLimit || size > left)
        return;
      left -= size;
      con->setAttr(stackMark, unit);
      ++marked.cells;
    });
  }
  return marked;
}

} // namespace idr::stack
