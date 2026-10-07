// idr.lower:words: the values cells, static data and patterns are built
// from: the pointer type, constant words as LLVM and arith write them, the
// address of a component of a cell and the alignment it has there, and the
// empty value of a counted component. The module's own, unexported.
module;
// The runtime's C ABI: the size of its words is a macro. llvm_unreachable
// is a macro.
#include "idris_rt.h"
#include "llvm/Support/ErrorHandling.h"

export module idr.lower:words;

import idr.mlir;
import idr.dialect;

using namespace mlir;

namespace idr::lower {

Type ptrType(MLIRContext *ctx) { return LLVM::LLVMPointerType::get(ctx); }

Value i64Constant(OpBuilder &b, Location loc, int64_t value) {
  return LLVM::ConstantOp::create(b, loc, b.getI64Type(), b.getI64IntegerAttr(value));
}

Value i32Constant(OpBuilder &b, Location loc, int64_t value) {
  return LLVM::ConstantOp::create(b, loc, b.getI32Type(),
                                  b.getI32IntegerAttr(static_cast<int32_t>(value)));
}

// The i64 constant `value`, as arith writes it.
Value constantI64(OpBuilder &b, Location loc, int64_t value) {
  return arith::ConstantOp::create(b, loc, b.getI64IntegerAttr(value));
}

Value at(OpBuilder &b, Location loc, Value cell, unsigned offset) {
  return LLVM::GEPOp::create(b, loc, ptrType(b.getContext()), b.getI8Type(), cell,
                             ArrayRef<LLVM::GEPArg>{static_cast<int32_t>(offset)});
}

// The alignment of the component at `offset` in a cell, which is
// word-aligned: LLVM would otherwise take the alignment of the type from a
// data layout that the translation does not have yet.
unsigned alignAt(unsigned offset) {
  return static_cast<unsigned>(llvm::MinAlign(IDRIS_RT_WORD_BYTES, offset));
}

// idr's comparison, as a signed comparison of the values. A big's small
// words and the runtime's three-way result both order that way.
arith::CmpIPredicate signedPredicate(CmpPredicate predicate) {
  switch (predicate) {
  case CmpPredicate::eq:
    return arith::CmpIPredicate::eq;
  case CmpPredicate::lt:
    return arith::CmpIPredicate::slt;
  case CmpPredicate::lte:
    return arith::CmpIPredicate::sle;
  case CmpPredicate::gt:
    return arith::CmpIPredicate::sgt;
  case CmpPredicate::gte:
    return arith::CmpIPredicate::sge;
  }
  llvm_unreachable("a comparison predicate");
}

// The empty value of a counted component: a null pointer, or the word 0.
Value nullComponent(OpBuilder &b, Location loc, Type component) {
  if (isa<LLVM::LLVMPointerType>(component))
    return LLVM::ZeroOp::create(b, loc, component);
  return LLVM::ConstantOp::create(b, loc, component, b.getIntegerAttr(component, 0));
}

} // namespace idr::lower
