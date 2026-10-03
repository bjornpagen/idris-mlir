// The cells idr-stack puts on the stack, as idr-lower builds them
// (Lower/Patterns.h).

#include "Lower/Patterns.h"

#include "idris_rt.h"

using namespace mlir;

namespace idr::lower {

Value stackCell(OpBuilder &b, Location loc, ConOp con, Layouts &layouts, Runtime &runtime) {
  if (!con->hasAttr(layout::stackMark) || runtime.isJit())
    return {};
  CtorOp ctor = lookupCtor(con, con.getCtor());
  const Cell &layout = layouts.box(ctor);
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
