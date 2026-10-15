// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What the dialect registers for idr.func, idr.call and idr.return beyond
// their ops: the inliner's rules, which mirror func's for its own; and what
// a call may do, which is its callee's, read through a symbol table.
#ifndef IDR_IR_FUNC_H
#define IDR_IR_FUNC_H

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/CallInterfaces.h"

namespace idr {

// Every call, op and region of the dialect may be inlined; a return becomes
// the values it gives back, or a branch when the callee has several blocks.
void addInlinerInterface(IdrDialect &dialect);

// What a function may do when nothing says less: perform IO, crash and not
// return.
inline constexpr Effect anyEffect = Effect::io | Effect::crash | Effect::diverge;

// What `call` may do: its callee's effects, the one copy, which `symbols`
// finds from the call. A callee that is a value (idr.apply, before
// idr-defunctionalize) is any function, and a function whose effects no
// pass has found yet may do anything.
Effect effectsOf(mlir::CallOpInterface call, mlir::SymbolTableCollection &symbols);

} // namespace idr

#endif // IDR_IR_FUNC_H
