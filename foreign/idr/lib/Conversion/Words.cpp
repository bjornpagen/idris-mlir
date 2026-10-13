// The words idr-lower builds cells, static data and patterns from.

#include "idr/IR/IdrDialect.h"
#include "idr/Conversion/Words.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "llvm/Support/MathExtras.h"

#include "idris_rt.h"

using namespace mlir;

namespace idr::conversion {

Type ptrType(MLIRContext *ctx) { return LLVM::LLVMPointerType::get(ctx); }

Value i64Constant(OpBuilder &b, Location loc, int64_t value) {
  return LLVM::ConstantOp::create(b, loc, b.getI64Type(), value);
}

Value i32Constant(OpBuilder &b, Location loc, int64_t value) {
  return LLVM::ConstantOp::create(b, loc, b.getI32Type(), value);
}

Value at(OpBuilder &b, Location loc, Value cell, unsigned offset) {
  return LLVM::GEPOp::create(b, loc, ptrType(b.getContext()), b.getI8Type(), cell,
                             ArrayRef<LLVM::GEPArg>{static_cast<int32_t>(offset)});
}

unsigned alignAt(unsigned offset) {
  return static_cast<unsigned>(llvm::MinAlign(IDRIS_RT_WORD_BYTES, offset));
}

Value nullComponent(OpBuilder &b, Location loc, Type component) {
  if (isa<LLVM::LLVMPointerType>(component))
    return LLVM::ZeroOp::create(b, loc, component);
  return LLVM::ConstantOp::create(b, loc, component, 0);
}

} // namespace idr::conversion
