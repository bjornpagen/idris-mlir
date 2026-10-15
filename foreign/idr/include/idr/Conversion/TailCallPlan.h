// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What idr-tail-calls decides on the whole module, before it rewrites any
// function: which calls become guaranteed tail calls, which functions take
// `tailcc`, and which results go through memory.

#ifndef IDR_CONVERSION_TAILCALLPLAN_H
#define IDR_CONVERSION_TAILCALLPLAN_H

#include "mlir/Analysis/CallGraph.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/BuiltinOps.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallVector.h"

#include <cstdint>

namespace idr::conversion {

// The plan of idr-tail-calls, computed once over the lowered module and
// read by the rewrite of each function, which reads nothing of another
// function but this. Making it mutates nothing.
//
//   - The internal functions: defined, private, not variadic, every user an
//     llvm.call naming it as callee. Only these take `tailcc`: a function
//     the runtime calls through a pointer (@main, @__idr_main) keeps C's.
//   - The candidates: calls of an internal function in tail position that
//     do not reach their caller's frame.
//   - The cycles of direct calls, the strongly connected components of the
//     call graph. A call to a declaration or through a pointer leads to the
//     graph's unknown callee, which is on no cycle of the program.
//   - The `tailcc` set: the callers and callees of candidates on one cycle.
//     A planned tail call is a candidate whose caller and callee are both
//     in it, and that the return after each planned call earlier in its
//     block, or on the only paths to it, leaves reachable.
//   - What goes through memory: among the callers and callees of planned
//     tail calls, those whose result does not fit the return registers.
class TailCallPlan {
public:
  // What the rewrite of one function does; nothing, for one the plan does
  // not name.
  struct Function {
    // Whether it takes `tailcc`.
    bool tail = false;
    // Its planned tail calls, each in a block the entry still reaches once
    // the return follows each of them.
    llvm::SmallVector<mlir::LLVM::CallOp> tailCalls;
    // Its calls of a function that takes `tailcc`.
    llvm::SmallVector<mlir::LLVM::CallOp> tailccCalls;
    // Whether its result goes through memory. Each of its planned tail
    // calls then passes on the pointer it got: a tail call returns its
    // callee's result as its caller's, of one type, so the callee's result
    // goes through memory too, and a caller whose result does not makes no
    // such call.
    bool resultInMemory = false;
    // Its other calls, in what the entry still reaches, of a function whose
    // result goes through memory: each passes a slot of its frame.
    llvm::SmallVector<mlir::LLVM::CallOp> throughSlot;
  };

  // The plan of `module`, whose cycles of direct calls are `graph`'s. A
  // failure, reported, when a result had to be measured and there is no
  // machine for the module's target to ask.
  static mlir::FailureOr<TailCallPlan> make(mlir::ModuleOp module, const mlir::CallGraph &graph);

  // What the rewrite of `fn` does.
  const Function &of(mlir::LLVM::LLVMFuncOp fn) const;

  // The calls in tail position that stay calls since they may reach their
  // caller's frame, and the functions whose result goes through memory.
  uint64_t frameBound() const { return bound; }
  uint64_t inMemory() const { return memory; }

private:
  TailCallPlan() = default;

  llvm::DenseMap<mlir::Operation *, Function> functions;
  uint64_t bound = 0;
  uint64_t memory = 0;
};

} // namespace idr::conversion

#endif // IDR_CONVERSION_TAILCALLPLAN_H
