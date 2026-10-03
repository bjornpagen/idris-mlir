// idr.lower:stackCell: the cells idr-stack puts on the stack, as idr-lower
// builds them.
module;
// The runtime's C ABI: the size of its words is a macro.
#include "idris_rt.h"

export module idr.lower:stackCell;

import idr.mlir;
import idr.dialect;
import idr.layout;

import :runtime;

using namespace mlir;

export namespace idr::lower {

// The cell of `con`, a box's constructor that idr-stack marked
// (layout::stackMark), before its fields: a slot in the entry block of the
// function that holds it, one slot per con, allocated once per frame however
// often the con runs, so LLVM may keep it in registers when it stays in the
// function. Its header, written where the con runs, is count 1 and the box's
// info with the stack mark (IDRIS_RT_STACK_CELL): counting works on it as on
// any cell, but when its count reaches 0 its memory is not freed, and it is
// never exclusive, so no reset reuses it for a value that could outlive the
// frame. Null when the con is not marked, or in JIT mode, whose arena cells
// are all persistent.
Value stackCell(OpBuilder &b, Location loc, ConOp con, layout::Layouts &layouts,
                Runtime &runtime) {
  if (!con->hasAttr(layout::stackMark) || runtime.isJit())
    return {};
  CtorOp ctor = lookupCtor(con, con.getCtor());
  const layout::Cell &layout = layouts.box(ctor);
  Value slot;
  {
    OpBuilder::InsertionGuard guard(b);
    b.setInsertionPointToStart(&con->getParentOfType<func::FuncOp>().getBody().front());
    Value one = LLVM::ConstantOp::create(b, loc, b.getI64Type(), b.getI64IntegerAttr(1));
    slot = LLVM::AllocaOp::create(b, loc, LLVM::LLVMPointerType::get(b.getContext()),
                                  LLVM::LLVMArrayType::get(b.getI8Type(), layout.size), one,
                                  /*alignment=*/IDRIS_RT_WORD_BYTES);
  }
  runtime.storeHeader(b, loc, slot, layout.info.onStack());
  return slot;
}

} // namespace idr::lower
