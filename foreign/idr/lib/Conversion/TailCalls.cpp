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
//     (private, its address never taken) takes `tailcc`: @main and
//     @__idr_main, which the runtime's entry calls through a pointer, keep
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
//     it takes (a cell idr-stack put there, or memory that holds one) stays
//     a call, since the frame has to outlive the callee. idr-stack puts on
//     the stack no cell that a call in tail position on its caller's cycle
//     takes, so such a call is never a recursion's: its callee, off the
//     cycle, never calls back round, and adds its frame once.
//
// What the pass decides needs the whole module: which functions only the
// module's calls reach, the cycles, which results go through memory and
// every call of a function whose signature changes. That is the plan
// (TailCallPlan), computed once; the rewrite is per function, and runs on
// every function at once, each reading only the plan.

#include "idr/Conversion/PassThroughMemory.h"
#include "idr/Conversion/Passes.h"
#include "idr/Conversion/TailCallPlan.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Support/TypeID.h"
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

// What the plan says of one function, done to it: its convention and that
// of its calls of `tailcc` functions; the return right after each planned
// tail call, and the blocks that leaves unreached gone; its result through
// memory and its calls of functions whose result goes there; then each
// planned call made `musttail`.
void place(LLVM::LLVMFuncOp fn, const TailCallPlan::Function &plan) {
  IRRewriter rewriter(fn.getContext());
  if (plan.tail)
    fn.setCConv(CConv::Tail);
  for (LLVM::CallOp call : plan.tailccCalls)
    call.setCConv(CConv::Tail);
  SmallVector<LLVM::CallOp> tailCalls(plan.tailCalls);
  for (LLVM::CallOp call : tailCalls) {
    Block *block = call->getBlock();
    rewriter.splitBlock(block, std::next(call->getIterator()));
    rewriter.setInsertionPointToEnd(block);
    LLVM::ReturnOp::create(rewriter, call.getLoc(), call.getResults());
  }
  if (!tailCalls.empty())
    (void)eraseUnreachableBlocks(rewriter, fn.getBody());
  Value out = plan.inMemory ? takeResultPointer(fn, rewriter) : Value();
  callThroughMemory(fn, plan.throughMemory, tailCalls, out, rewriter);
  if (out)
    storeResults(fn, out, rewriter);
  for (LLVM::CallOp call : tailCalls)
    call.setTailCallKind(TailCallKind::MustTail);
}

// The rewrite of one function, run by idr-tail-calls over every function
// of the module from the plan it computed just before.
struct Place : PassWrapper<Place, OperationPass<LLVM::LLVMFuncOp>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(Place)

  StringRef getArgument() const override { return "idr-tail-calls-place"; }

  void runOnOperation() override {
    LLVM::LLVMFuncOp fn = getOperation();
    auto plan = getCachedParentAnalysis<TailCallPlan>();
    if (!plan) {
      fn.emitError("internal error: idr-tail-calls-place: no tail-call plan for the module");
      return signalPassFailure();
    }
    if (const TailCallPlan::Function *work = plan->get().of(fn))
      place(fn, *work);
  }
};

struct TailCalls : idr::impl::IdrTailCallsBase<TailCalls> {
  using IdrTailCallsBase::IdrTailCallsBase;

  void runOnOperation() override {
    ModuleOp module = getOperation();
    {
      // The nested pipeline drops every analysis of the module, the plan
      // with it, so what the statistics need is copied first.
      const TailCallPlan &plan = getAnalysis<TailCallPlan>();
      if (failed(plan.target()))
        return signalPassFailure();
      numFrameBound += plan.frameBound();
      numInMemory += plan.inMemory();
    }
    OpPassManager places(ModuleOp::getOperationName());
    places.nest<LLVM::LLVMFuncOp>().addPass(std::make_unique<Place>());
    if (failed(runPipeline(places, module)))
      return signalPassFailure();
    module.walk([&](LLVM::CallOp call) {
      if (call.getTailCallKind() == TailCallKind::MustTail)
        ++numTailCalls;
    });
  }
};

} // namespace

} // namespace idr::conversion
