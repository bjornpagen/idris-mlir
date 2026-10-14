// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Phase 0 of idr-lower: the program's functions as the dialects bound for
// LLVM name them.

#ifndef IDR_CONVERSION_FUNCTOFUNC_H
#define IDR_CONVERSION_FUNCTOFUNC_H

#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/SymbolTable.h"

namespace idr::conversion {

// Every idr.func becomes a func.func at the same location, of the same type
// and visibility, named by its mangled symbol, with its body and none of its
// facts; every idr.call a func.call of the mangled callee, and every
// idr.return a func.return. `symbols`, the module's table, follows each
// function under its new name. For the walk driver, which visits a body
// before its function.
void populateFuncToFuncPatterns(mlir::RewritePatternSet &patterns, mlir::SymbolTable &symbols);

} // namespace idr::conversion

#endif // IDR_CONVERSION_FUNCTOFUNC_H
