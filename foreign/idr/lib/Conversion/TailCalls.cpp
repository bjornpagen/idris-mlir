// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-tail-calls: where each call stands, made what LLVM obeys. A call in
// tail position never grows the stack: it is an idr.tail_call, whose
// verifier held every pass to it, and idr-lower made it a `musttail` call
// under `tailcc`, the convention every function of the program takes.
// Nothing here decides which call is one, or keeps a call it could not
// make: a `musttail` call LLVM cannot make fails to compile, never silently
// a call.
//
//   - The return. The lowering gives a call's results back through the
//     components it took apart and the branches the matches became, and
//     the idr verifier proved they reach the return unchanged; LLVM wants
//     the return right after the call. Each `musttail` call's block ends
//     there with the return of the call's result, and what followed it no
//     longer runs.
//   - Results the target returns in memory. A result that does not fit the
//     return registers would come back through a hidden pointer into the
//     caller's frame, and LLVM makes no tail call of such a call. What fits
//     is the target's own answer, for the module's #llvm.target, and a fact
//     of the result's type alone: every function of the program whose
//     result does not fit takes a pointer to write it to instead, first,
//     and returns nothing. A tail call passes on the pointer its caller
//     got (its result is its caller's, so of the same type), any other call
//     a slot of its own frame, which it reads back. The hidden pointer
//     LLVM would make costs the same; this one a tail call can pass on.
//
// LLVM's verifier is the last check: a `musttail` call whose result is not
// its function's, or whose callee takes another convention, is refused
// there, as the internal error it is.

#include "idr/Conversion/PassThroughMemory.h"
#include "idr/Conversion/Passes.h"
#include "idr/Conversion/ReturnRegisters.h"
#include "idr/Support/Footprint.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/Threading.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Transforms/RegionUtils.h"

#include <cstdint>

#define GEN_PASS_DEF_IDRTAILCALLS
#include "idr/IR/Generated/PassDialects.h.inc"

namespace idr {
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::conversion {

namespace {

using LLVM::cconv::CConv;
using LLVM::tailcallkind::TailCallKind;

// Where a result of the program's convention comes back: in the return
// registers, or written through a pointer its caller passes.
enum class Returned : std::uint8_t { InRegisters, ThroughMemory };

// `fn`'s `musttail` calls, each its block's last op but the return of its
// result: the rest of the block moves to a block of its own, which, like
// every block the entry no longer reaches, goes.
SmallVector<LLVM::CallOp> endAtTailCalls(LLVM::LLVMFuncOp fn) {
  IRRewriter rewriter(fn.getContext());
  SmallVector<LLVM::CallOp> tailCalls;
  fn.walk([&](LLVM::CallOp call) {
    if (call.getTailCallKind() == TailCallKind::MustTail)
      tailCalls.push_back(call);
  });
  for (LLVM::CallOp call : tailCalls) {
    Block *block = call->getBlock();
    rewriter.splitBlock(block, std::next(call->getIterator()));
    rewriter.setInsertionPointToEnd(block);
    LLVM::ReturnOp::create(rewriter, call.getLoc(), call.getResults());
  }
  (void)eraseUnreachableBlocks(rewriter, fn.getBody());
  return tailCalls;
}

// `fn`, its `musttail` calls `tailCalls`, with each result of the
// program's convention that does not fit the registers going through
// memory: its own, if it takes the convention, and each of its calls'. The
// entry, of C's convention, calls the program's root so too.
void throughMemory(LLVM::LLVMFuncOp fn, SmallVectorImpl<LLVM::CallOp> &tailCalls,
                   ReturnRegisters &registers) {
  IRRewriter rewriter(fn.getContext());
  auto returned = [&](Type type) {
    return registers.fit(type) ? Returned::InRegisters : Returned::ThroughMemory;
  };
  SmallVector<LLVM::CallOp> slots;
  fn.walk([&](LLVM::CallOp call) {
    if (call.getCConv() != CConv::Tail || call.getTailCallKind() == TailCallKind::MustTail ||
        call.getNumResults() != 1)
      return;
    if (returned(call.getResult().getType()) == Returned::ThroughMemory)
      slots.push_back(call);
  });
  if (fn.getCConv() == CConv::Tail &&
      returned(fn.getFunctionType().getReturnType()) == Returned::ThroughMemory) {
    Value out = takeResultPointer(fn, rewriter);
    passOnPointer(tailCalls, out, rewriter);
    storeResults(fn, out, rewriter);
  }
  callThroughSlots(fn, slots, rewriter);
}

struct TailCalls : idr::impl::IdrTailCallsBase<TailCalls> {
  using IdrTailCallsBase::IdrTailCallsBase;

  // Each function on its own: its returns in parallel; then its results,
  // serially, since the target's answers are asked once per type and kept.
  void runOnOperation() override {
    ModuleOp module = getOperation();
    FailureOr<ReturnRegisters> registers = ReturnRegisters::of(module);
    if (failed(registers))
      return signalPassFailure();
    footprint::Vector<LLVM::LLVMFuncOp> functions;
    for (auto fn : module.getOps<LLVM::LLVMFuncOp>())
      if (!fn.isExternal())
        functions.push_back(fn);
    footprint::Vector<SmallVector<LLVM::CallOp>> tailCalls(functions.size());
    parallelFor(&getContext(), 0, functions.size(),
                [&](size_t at) { tailCalls[at] = endAtTailCalls(functions[at]); });
    for (auto [fn, calls] : llvm::zip_equal(functions, tailCalls))
      throughMemory(fn, calls, *registers);
  }
};

} // namespace

} // namespace idr::conversion
