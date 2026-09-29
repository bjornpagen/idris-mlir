// The stack slots of the cells idr-stack marks (Stack/Cell.h).

#include "Stack/Cell.h"

using namespace mlir;

namespace idr::stack {

bool onStack(ConOp con) { return con->hasAttr(mark); }

Value slot(OpBuilder &b, Location loc, ConOp con, unsigned size) {
  OpBuilder::InsertionGuard guard(b);
  b.setInsertionPointToStart(&con->getParentOfType<func::FuncOp>().getBody().front());
  auto i64 = b.getI64Type();
  Value one = LLVM::ConstantOp::create(b, loc, i64, b.getI64IntegerAttr(1));
  return LLVM::AllocaOp::create(b, loc, LLVM::LLVMPointerType::get(b.getContext()),
                                LLVM::LLVMArrayType::get(i64, size / 8), one,
                                /*alignment=*/8);
}

} // namespace idr::stack
