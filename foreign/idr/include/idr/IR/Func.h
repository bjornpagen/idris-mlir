// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What the dialect registers for idr.func, idr.call and idr.return beyond
// their ops: the inliner's rules, which mirror func's for its own; and what
// a function's body does of itself. What a call may do is its callee's,
// which idr::ownEffects reads through the table of a CalleeEffects
// (Flow.h).
#ifndef IDR_IR_FUNC_H
#define IDR_IR_FUNC_H

#include "idr/IR/IdrDialect.h"

namespace idr {

// Every call, op and region of the dialect may be inlined; a return becomes
// the values it gives back, or a branch when the callee has several blocks.
void addInlinerInterface(IdrDialect &dialect);

// What `fn`'s body does of itself, its calls aside: not return unless Idris
// proved it total; perform IO where a parameter may hold a world or the
// body forges one; crash where an op may crash. The one rule: idr-effects'
// solve and the program's verifier both read it. The ops' memory effects
// are not it: a possible crash also writes the IO resource, and an op may
// read that resource with no world.
Effect bodyEffect(FuncOp fn);

} // namespace idr

#endif // IDR_IR_FUNC_H
