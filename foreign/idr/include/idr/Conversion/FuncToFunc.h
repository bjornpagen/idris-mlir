// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Phase 0 of idr-lower: the program's functions as the dialects bound for
// LLVM name them.

#ifndef IDR_CONVERSION_FUNCTOFUNC_H
#define IDR_CONVERSION_FUNCTOFUNC_H

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/SymbolTable.h"

namespace idr::conversion {

// Every idr.func of `program` becomes, where it is, a func.func at the
// same location, of the same type, named by its mangled symbol, with its
// body and none of its facts: private, but for the program's root, which
// the outside enters and so stays public. The program's root then names it
// by that name. Every idr.call becomes a func.call of the mangled callee,
// and every idr.return a func.return. `symbols`, the program's table,
// follows each function under its new name. Fails, having reported it,
// where a name meets another symbol of the program.
mlir::LogicalResult lowerFunctions(ProgramOp program, mlir::SymbolTable &symbols);

} // namespace idr::conversion

#endif // IDR_CONVERSION_FUNCTOFUNC_H
