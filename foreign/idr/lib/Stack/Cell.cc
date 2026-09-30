// The cells idr-stack puts on the stack (Stack/Cell.h).

#include "Stack/Cell.h"

#include "idris_rt.h"

using namespace mlir;

namespace idr::stack {

Value cell(OpBuilder &b, Location loc, ConOp con, lower::Layouts &layouts,
           lower::Runtime &runtime) {
  if (!con->hasAttr(mark) || runtime.isJit())
    return {};
  CtorOp ctor = lookupCtor(con, con.getCtor());
  const lower::Cell &layout = layouts.box(ctor);
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

} // namespace idr::stack
