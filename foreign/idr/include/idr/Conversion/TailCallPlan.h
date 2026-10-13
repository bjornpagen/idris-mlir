// What idr-tail-calls decides on the whole module, before it rewrites any
// function: which calls become guaranteed tail calls, which functions take
// `tailcc`, and which results go through memory.

#ifndef IDR_CONVERSION_TAILCALLPLAN_H
#define IDR_CONVERSION_TAILCALLPLAN_H

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Pass/AnalysisManager.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallVector.h"

namespace idr::conversion {

// The plan of idr-tail-calls, computed once over the lowered module and
// read by the rewrite of each function, which reads nothing of another
// function but this. None of it mutates the module.
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
  // A call of a function whose result goes through memory: the result it
  // returned, and the callee's type once it takes the pointer.
  struct ThroughMemory {
    mlir::LLVM::CallOp call;
    mlir::Type result;
    mlir::LLVM::LLVMFunctionType type;
  };

  // What the rewrite of one function does.
  struct Function {
    // Whether it takes `tailcc`, and whether its result goes through
    // memory.
    bool tail = false;
    bool inMemory = false;
    // Its planned tail calls, each in a block the entry still reaches once
    // the return follows each of them.
    llvm::SmallVector<mlir::LLVM::CallOp> tailCalls;
    // Its calls of a function that takes `tailcc`.
    llvm::SmallVector<mlir::LLVM::CallOp> tailccCalls;
    // Its calls, in what the entry still reaches, of a function whose
    // result goes through memory.
    llvm::SmallVector<ThroughMemory> throughMemory;
  };

  TailCallPlan(mlir::Operation *module, mlir::AnalysisManager &am);

  bool isInvalidated(const mlir::AnalysisManager::PreservedAnalyses &pa) const {
    return !pa.isPreserved<TailCallPlan>();
  }

  // A failure when a result had to be measured and there is no machine for
  // the module's target to ask, which has been reported.
  mlir::LogicalResult target() const { return mlir::success(machine); }

  // What the rewrite of `fn` does, or null when it does nothing.
  const Function *of(mlir::LLVM::LLVMFuncOp fn) const;

  // The calls in tail position that stay calls since they may reach their
  // caller's frame, and the functions whose result goes through memory.
  uint64_t frameBound() const { return bound; }
  uint64_t inMemory() const { return memory; }

private:
  llvm::DenseMap<mlir::Operation *, Function> functions;
  bool machine = true;
  uint64_t bound = 0;
  uint64_t memory = 0;
};

} // namespace idr::conversion

#endif // IDR_CONVERSION_TAILCALLPLAN_H
