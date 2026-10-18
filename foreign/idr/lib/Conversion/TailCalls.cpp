// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-tail-calls: every call the program makes in tail position on a cycle
// of calls is a guaranteed tail call, so that a recursion through such calls
// runs in constant stack. Idris has no loop but recursion: an IO loop or a
// mutual recursion in tail position must not grow the stack; idr-tail-loops
// makes only a function's calls of itself loops.
//
// The pass runs last, on the LLVM dialect, where the control flow is final.
//
//   - Which calls. A call in tail position matters where its callee is on
//     its caller's cycle of calls: a recursion keeps a frame per round
//     unless each of its calls is a tail call. A call from one cycle to
//     another adds its caller's frame once at most, since the callee never
//     calls back, so it is left an ordinary call, which costs nothing. The
//     cycles are those of direct calls: no call through a pointer is a tail
//     call, so a cycle through one keeps that call's frame anyway.
//   - The calling convention. The caller and the callee of such a call take
//     LLVM's `tailcc`, and so do all their calls: fastcc's registers, with
//     the guarantee that a call in tail position is a tail call, whose stack
//     arguments the callee pops. The popping costs every call of such a
//     function (on x86-64 a slot that keeps the stack aligned, which the
//     callee pops even when there is no stack argument and the caller takes
//     back), so the other functions keep C's convention, which LLVM makes
//     fastcc. Only a function that only the module's own calls reach
//     (private, its address never taken) takes `tailcc`: @main and the
//     entry body, which the runtime's entry calls through a pointer, keep
//     C's. Calls of the runtime's C functions stay calls of C: the runtime
//     never calls back, so no recursion runs through one.
//   - Tail position. A call of a `tailcc` function from one is in tail
//     position when the path from it decides, by what it sees alone, to
//     return the call's result unchanged: through extractvalue and
//     insertvalue that take the result apart and put it back together,
//     through branches whose block arguments carry it, past conditions the
//     path decides (the exit flag a loop's tail passes as a constant) and
//     past ops that only compute. The call becomes `musttail`, with the
//     return moved right after it: LLVM then emits a tail call or fails to
//     compile, never silently a call.
//   - Results the target returns in memory. A result that does not fit the
//     return registers would come back through a hidden pointer into the
//     caller's frame, and LLVM makes no tail call of such a call. What fits
//     is the target's own answer: LLVM's lowering of `tailcc` is asked, for
//     the module's #llvm.target. Each function on a tail call whose result
//     does not fit takes a pointer to write its result to instead, first,
//     and returns nothing: a tail call passes on the pointer its caller got,
//     any other call a slot of its own frame, which it reads back.
//   - A frame's cells. A call that may reach its caller's frame through what
//     it takes (a cell idr-rc-stack put there, or memory that holds one) stays
//     a call, since the frame has to outlive the callee. idr-rc-stack puts on
//     the stack no cell that a call in tail position on its caller's cycle
//     takes, so such a call is never a recursion's: its callee, off the
//     cycle, never calls back round, and adds its frame once.
//
// What the pass decides needs the whole module: which functions only the
// module's calls reach, the cycles, and which results go through memory,
// which make each function's convention, a fact its callers read. That is
// the plan (TailCallPlan), computed once; the rewrite is per function, and
// runs on every function at once, each reading only the plan.

#include "idr/Analysis/CallCycles.h"
#include "idr/Conversion/PassThroughMemory.h"
#include "idr/Conversion/Passes.h"
#include "idr/Conversion/TailCallPlan.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/Threading.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Transforms/RegionUtils.h"

namespace idr {
#define GEN_PASS_DEF_IDRTAILCALLS
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::conversion {

namespace {

using LLVM::cconv::CConv;
using LLVM::tailcallkind::TailCallKind;

// What the plan says of `fn`, done to it, in the order the rewrite needs:
// its own convention; the return right after each of its planned tail
// calls, and the blocks the entry no longer reaches gone, so that no call is
// left that would keep its callee's old signature; then each call left takes
// its callee's convention, read from the plan, before any call is made
// again, since a call made again keeps the convention of the one it
// replaces; its result through memory, and its other calls of functions
// whose result goes there through slots of its frame; then each planned
// call made `musttail`.
void place(LLVM::LLVMFuncOp fn, const TailCallPlan &plan) {
  IRRewriter rewriter(fn.getContext());
  Convention own = plan.conventionOf(fn.getSymNameAttr());
  if (own != Convention::C)
    fn.setCConv(CConv::Tail);
  SmallVector<LLVM::CallOp> tailCalls(plan.tailCallsOf(fn));
  for (LLVM::CallOp call : tailCalls) {
    Block *block = call->getBlock();
    rewriter.splitBlock(block, std::next(call->getIterator()));
    rewriter.setInsertionPointToEnd(block);
    LLVM::ReturnOp::create(rewriter, call.getLoc(), call.getResults());
  }
  (void)eraseUnreachableBlocks(rewriter, fn.getBody());
  SmallVector<LLVM::CallOp> slots;
  fn.walk([&](LLVM::CallOp call) {
    // A call through a pointer names no callee, and every function the plan
    // gives another convention is called only directly: it stays C's.
    FlatSymbolRefAttr callee = call.getCalleeAttr();
    if (!callee)
      return;
    Convention convention = plan.conventionOf(callee.getAttr());
    if (convention == Convention::C)
      return;
    call.setCConv(CConv::Tail);
    if (convention == Convention::TailThroughMemory && !llvm::is_contained(tailCalls, call))
      slots.push_back(call);
  });
  if (own == Convention::TailThroughMemory) {
    Value out = takeResultPointer(fn, rewriter);
    passOnPointer(tailCalls, out, rewriter);
    storeResults(fn, out, rewriter);
  }
  callThroughSlots(fn, slots, rewriter);
  for (LLVM::CallOp call : tailCalls)
    call.setTailCallKind(TailCallKind::MustTail);
}

struct TailCalls : idr::impl::IdrTailCallsBase<TailCalls> {
  using IdrTailCallsBase::IdrTailCallsBase;

  // The plan is the module's; the rewrite then runs on every function at
  // once, each reading only the plan and its own body.
  void runOnOperation() override {
    ModuleOp module = getOperation();
    FailureOr<TailCallPlan> plan = TailCallPlan::make(module, getAnalysis<CallCycles>());
    if (failed(plan))
      return signalPassFailure();
    numFrameBound += plan->frameBound();
    numInMemory += plan->inMemory();
    SmallVector<LLVM::LLVMFuncOp> functions;
    for (auto fn : module.getOps<LLVM::LLVMFuncOp>())
      if (!fn.isExternal())
        functions.push_back(fn);
    parallelForEach(&getContext(), functions, [&](LLVM::LLVMFuncOp fn) { place(fn, *plan); });
    module.walk([&](LLVM::CallOp call) {
      if (call.getTailCallKind() == TailCallKind::MustTail)
        ++numTailCalls;
    });
  }
};

} // namespace

} // namespace idr::conversion
