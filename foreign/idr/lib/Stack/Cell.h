// The stack slots of the cells idr-stack marks, as idr-lower builds them.
#pragma once

#include "idr/Idr.h"

namespace idr::stack {

// The unit attribute of an idr.con whose cell idr-stack puts on the stack.
inline constexpr llvm::StringLiteral mark = "idr.stack";

// Whether idr-stack put the cell of `con` on the stack (`idr.stack`).
bool onStack(ConOp con);

// A slot of `size` bytes, 8-byte aligned, for the cell of `con`, in the
// entry block of the function that holds it: one slot per con, allocated
// once per frame however often the con runs, which LLVM may keep in
// registers when the cell stays in the function. The caller writes the
// header, with the stack mark, and the fields.
mlir::Value slot(mlir::OpBuilder &b, mlir::Location loc, ConOp con, unsigned size);

} // namespace idr::stack
