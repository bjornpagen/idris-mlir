// The cells idr-stack puts on the stack, as idr-lower builds them.
#pragma once

#include "Lower/Runtime.h"

namespace idr::stack {

// The unit attribute of an idr.con whose cell idr-stack puts on the stack.
inline constexpr llvm::StringLiteral mark = "idr.stack";

// The cell of `con`, a box's constructor that idr-stack marked, before its
// fields: a slot in the entry block of the function that holds it, one slot
// per con, allocated once per frame however often the con runs, so LLVM may
// keep it in registers when it stays in the function. Its header, written
// where the con runs, is count 1 and the box's info with the stack mark
// (IDRIS_RT_STACK_CELL): counting works on it as on any cell, but when its
// count reaches 0 its memory is not freed, and it is never exclusive, so no
// reset reuses it for a value that could outlive the frame. Null when the
// con is not marked, or in JIT mode, whose arena cells are all persistent.
mlir::Value cell(mlir::OpBuilder &b, mlir::Location loc, ConOp con, lower::Layouts &layouts,
                 lower::Runtime &runtime);

} // namespace idr::stack
