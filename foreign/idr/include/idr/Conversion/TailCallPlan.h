// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What idr-tail-calls decides on the whole module, before it rewrites any
// function: each function's calling convention and its planned tail calls.

#ifndef IDR_CONVERSION_TAILCALLPLAN_H
#define IDR_CONVERSION_TAILCALLPLAN_H

#include "idr/Analysis/CallCycles.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/BuiltinOps.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallVector.h"

#include <cstdint>

namespace idr::conversion {

// How a function is called, one fact of the function that its callers read:
// C's convention; `tailcc`; or `tailcc` with the result written through a
// pointer the caller passes first, the function returning nothing, since the
// result does not fit the return registers and LLVM makes no tail call of a
// call that returns in memory. Only a function on a planned tail call goes
// through memory: a tail call returns its callee's result as its caller's,
// of one type, so a tail call's caller and callee go through memory alike.
enum class Convention { C, Tail, TailThroughMemory };

// The plan of idr-tail-calls, computed once over the lowered module and
// read by the rewrite of each function, which reads nothing of another
// function but this. Making it mutates nothing.
//
//   - The internal functions: defined, private, not variadic, every user an
//     llvm.call naming it as callee. Only these take `tailcc`: a function
//     the runtime calls through a pointer (@main, the entry body) keeps C's.
//   - The candidates: calls of an internal function in tail position that
//     do not reach their caller's frame.
//   - The cycles of direct calls (CallCycles). A call to a declaration or
//     through a pointer leads to the graph's unknown callee, which is on no
//     cycle of the program.
//   - The `tailcc` functions: the callers and callees of candidates on one
//     cycle. A planned tail call is a candidate whose caller and callee both
//     take `tailcc`, and that the return after each planned call earlier in
//     its block, or on the only paths to it, leaves reachable.
//   - What goes through memory: among the callers and callees of planned
//     tail calls, those whose result does not fit the return registers.
class TailCallPlan {
public:
  // The plan of `module`, whose cycles of direct calls are `cycles`. A
  // failure, reported, when a result had to be measured and there is no
  // machine for the module's target to ask.
  static mlir::FailureOr<TailCallPlan> make(mlir::ModuleOp module, const CallCycles &cycles);

  // How the function named `callee` is called. A function the plan names
  // nothing of (a declaration, the runtime's, one on no planned cycle) is
  // called as C calls, the problem's default.
  Convention conventionOf(mlir::StringAttr callee) const;

  // The planned tail calls of `fn`, each in a block the entry still
  // reaches once the return follows each of them; none for most functions.
  llvm::ArrayRef<mlir::LLVM::CallOp> tailCallsOf(mlir::LLVM::LLVMFuncOp fn) const;

  // The calls in tail position that stay calls since they may reach their
  // caller's frame, and the functions whose result goes through memory.
  uint64_t frameBound() const { return bound; }
  uint64_t inMemory() const { return memory; }

private:
  TailCallPlan() = default;

  llvm::DenseMap<mlir::StringAttr, Convention> conventions;
  llvm::DenseMap<mlir::Operation *, llvm::SmallVector<mlir::LLVM::CallOp>> tailCalls;
  uint64_t bound = 0, memory = 0;
};

} // namespace idr::conversion

#endif // IDR_CONVERSION_TAILCALLPLAN_H
