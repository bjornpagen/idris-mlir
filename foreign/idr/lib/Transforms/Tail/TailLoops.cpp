// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
//===- TailLoops.cpp - idr-tail-loops -------------------------------------===//
//
// A function's self tail calls become one loop: a recursive join point
// whose region is the old body, each self tail call a jump back to it
// (idr::joins::loopSelf, the one construction of join points). A call
// whose fact is `tail` is in tail position by the verifier's word, so the
// jump that replaces it is a tail transfer, and nothing after it runs.
//
// The loop is an optimization over the guarantee, not the guarantee: a
// self tail call left a call is `musttail` at the lowering and grows no
// stack either. So the loop is an action a debug counter may skip.
//
// Whether the loop may run forever is its function's derived row, which
// the loop leaves as it was: an unused loop of code Idris did not prove to
// end stays, as eager evaluation keeps it, by the row and no mark of its
// own.
//
// The pass reads its own function and nothing else, and changes nothing
// outside it.
//
//===----------------------------------------------------------------------===//

#include "idr/Transforms/Tail.h"

#include "idr/IR/IdrDialect.h"
#include "idr/Support/Actions.h"
#include "idr/Transforms/Joins.h"

#include "mlir/IR/PatternMatch.h"
#include "mlir/Pass/Pass.h"

namespace idr {
#define GEN_PASS_DEF_IDRTAILLOOPS
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::tail {
namespace {

// idr-tail-loops makes one function's self tail calls a loop; the unit is
// the function.
struct TailLoopAction : support::TaggedAction<TailLoopAction> {
  using TaggedAction::TaggedAction;
  static constexpr llvm::StringLiteral tag = "idr-tail-loops-loop";
};

struct TailLoops : impl::IdrTailLoopsBase<TailLoops> {
  // The staged base finds the program and checks its stage; the pass reads
  // only its own function.
  void runOnProgram(ProgramOp) {
    FuncOp fn = getOperation();
    llvm::SmallVector<joins::Site> calls;
    fn.walk([&](CallOp call) {
      if (call.getTailKind() == TailKind::tail &&
          call.getCalleeAttr().getAttr() == fn.getSymNameAttr())
        calls.push_back(joins::Site{call, 0, call.getArgs(), call.getIndexArgsAttr()});
    });
    if (calls.empty())
      return markAllAnalysesPreserved();
    IRRewriter rewriter(fn.getContext());
    if (!support::perform<TailLoopAction>(fn, [&] {
          joins::loopSelf(rewriter, fn, calls);
          ++numLoops;
        }))
      return markAllAnalysesPreserved();
  }
};

} // namespace
} // namespace idr::tail
